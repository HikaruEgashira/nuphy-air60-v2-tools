// kvm-switch: switch the external display input when a Bluetooth keyboard
// connects to or leaves this Mac.
// usage: kvm-switch --connect <input> [--disconnect <input>] [--vendor 0x19f5] [--delay 1.5]
// DELL input codes (VCP 0x60): HDMI1=17 (0x11), HDMI2=18 (0x12), DP=15, USB-C=27.
import Foundation
import IOKit.hid
setvbuf(stdout, nil, _IONBF, 0)

var onConnect: UInt16?; var onDisconnect: UInt16?; var vendor = 0x19f5; var delay = 1.5
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

final class Watcher {
  var present = 0
  var pending: DispatchWorkItem?
  func changed(_ delta: Int) {
    let was = present > 0
    present = max(0, present + delta)
    let now = present > 0
    guard was != now else { return }
    pending?.cancel()
    let work = DispatchWorkItem { [self] in
      guard (present > 0) == now else { return }
      if let v = now ? onConnect : onDisconnect {
        print(Date(), now ? "keyboard connected" : "keyboard left", "-> input", v)
        DispatchQueue.global().async {
          let ok = ddcSetInput(v)
          DispatchQueue.main.async { print(Date(), "input", v, ok ? "confirmed" : "NOT confirmed") }
        }
      }
    }
    pending = work
    // Connect switches immediately; disconnect waits so a brief reconnect is ignored.
    DispatchQueue.main.asyncAfter(deadline: .now() + (now ? 0 : delay), execute: work)
  }
}
let w = Watcher()
let ctx = Unmanaged.passUnretained(w).toOpaque()
let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [
  kIOHIDVendorIDKey: vendor, kIOHIDTransportKey: "Bluetooth Low Energy",
  kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 6,
] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(m, { c, _, _, _ in Unmanaged<Watcher>.fromOpaque(c!).takeUnretainedValue().changed(1) }, ctx)
IOHIDManagerRegisterDeviceRemovalCallback(m, { c, _, _, _ in Unmanaged<Watcher>.fromOpaque(c!).takeUnretainedValue().changed(-1) }, ctx)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
print("open", IOHIDManagerOpen(m, 0), "connect ->", onConnect as Any, "disconnect ->", onDisconnect as Any)
CFRunLoopRun()
