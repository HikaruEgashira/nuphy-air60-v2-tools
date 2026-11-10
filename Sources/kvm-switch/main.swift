// kvm-switch: switch the external display input when a Bluetooth keyboard
// connects to or leaves this Mac.
// usage: kvm-switch --connect <input> [--disconnect <input>] [--vendor 0x19f5] [--delay 3.0]
// DELL input codes (VCP 0x60): HDMI1=17 (0x11), HDMI2=18 (0x12), DP=15, USB-C=27.
import Foundation
import IOKit.hid
setvbuf(stdout, nil, _IONBF, 0)

var onConnect: UInt16?; var onDisconnect: UInt16?; var vendor = 0x19f5; var delay = 3.0
var it = CommandLine.arguments.dropFirst().makeIterator()
func num(_ s: String?) -> Int { guard let s else { return -1 }; return s.hasPrefix("0x") ? Int(s.dropFirst(2), radix: 16) ?? -1 : Int(s) ?? -1 }
while let k = it.next() {
  switch k {
  case "--connect": onConnect = UInt16(exactly: num(it.next()))
  case "--disconnect": onDisconnect = UInt16(exactly: num(it.next()))
  case "--vendor": vendor = num(it.next())
  case "--delay": delay = Double(it.next() ?? "") ?? delay
  default: print("unknown option \(k)"); exit(64)
  }
}
guard onConnect != nil || onDisconnect != nil else { print("usage: kvm-switch --connect <input> [--disconnect <input>]"); exit(64) }

/// Asks the kvm firmware for its link mode over VIA raw HID (USB only).
/// Returns nil when no USB keyboard answers (stock firmware or not wired).
func linkModeOverUSB() -> UInt8? {
  let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
  IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: vendor, kIOHIDPrimaryUsagePageKey: 0xFF60] as CFDictionary)
  guard IOHIDManagerOpen(m, 0) == kIOReturnSuccess,
        let d = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>)?.first,
        IOHIDDeviceOpen(d, 0) == kIOReturnSuccess else { return nil }
  defer { IOHIDDeviceClose(d, 0); IOHIDManagerClose(m, 0) }
  var out = [UInt8](repeating: 0, count: 32); out[0] = 0x08; out[1] = 0x00; out[2] = 0x01
  guard IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0, out, 32) == kIOReturnSuccess else { return nil }
  for _ in 0..<20 {
    var buf = [UInt8](repeating: 0, count: 32); var len = CFIndex(32)
    if IOHIDDeviceGetReport(d, kIOHIDReportTypeInput, 0, &buf, &len) == kIOReturnSuccess, buf[0] == 0x08, buf[2] == 0x01 { return buf[3] }
    usleep(20_000)
  }
  return nil
}
let linkUSB: UInt8 = 4

final class Watcher {
  var ble = 0, usb = 0
  var pending: DispatchWorkItem?
  var generation = 0
  var last: Bool?
  /// On this Mac = Bluetooth link to this Mac, or a USB cable to this Mac while the
  /// keyboard is in wired mode. A cable in Bluetooth mode is only charging.
  func onThisMac() -> Bool {
    if ble > 0 { return true }
    guard usb > 0 else { return false }
    guard let mode = linkModeOverUSB() else { return true }  // stock firmware: assume wired
    return mode == linkUSB
  }
  func update() {
    let now = onThisMac()
    guard now != last else { return }
    let first = last == nil
    last = now
    pending?.cancel()
    generation += 1
    let gen = generation
    let work = DispatchWorkItem { [self] in
      guard onThisMac() == now else { last = !now; return }
      if let v = now ? onConnect : onDisconnect {
        print(Date(), now ? "keyboard on this Mac" : "keyboard left", "-> input", v)
        DispatchQueue.global().async {
          let ok = ddcSetInput(v)
          DispatchQueue.main.async { print(Date(), "input", v, ok ? "confirmed" : "NOT confirmed") }
          // The monitor's input auto-select can fall back to a live input while the
          // target host is still waking up; hold the input for a while.
          for _ in 0..<10 {
            sleep(3)
            guard self.generation == gen else { return }
            if let av = services().first, let cur = ddcRead(av, 0x60), cur & 0xff != v & 0xff {
              let again = ddcSetInput(v)
              DispatchQueue.main.async { print(Date(), "input reverted to", cur & 0xff, "-> reapplied", v, again) }
            }
          }
        }
      }
    }
    pending = work
    // Arriving switches immediately; leaving waits so a BLE/USB handover is ignored.
    DispatchQueue.main.asyncAfter(deadline: .now() + (now || first ? 0 : delay), execute: work)
  }
}
let w = Watcher()
let ctx = Unmanaged.passUnretained(w).toOpaque()
func transport(_ d: IOHIDDevice) -> String { IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? "" }
let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: vendor, kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 6] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(m, { c, _, _, d in
  let w = Unmanaged<Watcher>.fromOpaque(c!).takeUnretainedValue()
  if transport(d) == "USB" { w.usb += 1 } else { w.ble += 1 }
  w.update()
}, ctx)
IOHIDManagerRegisterDeviceRemovalCallback(m, { c, _, _, d in
  let w = Unmanaged<Watcher>.fromOpaque(c!).takeUnretainedValue()
  if transport(d) == "USB" { w.usb = max(0, w.usb - 1) } else { w.ble = max(0, w.ble - 1) }
  w.update()
}, ctx)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
print("open", IOHIDManagerOpen(m, 0), "connect ->", onConnect as Any, "disconnect ->", onDisconnect as Any)
// The rear mode switch changes wired/Bluetooth without any USB event; poll while a cable is attached.
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in if w.usb > 0 { w.update() } }
CFRunLoopRun()
