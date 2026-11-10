import IOKit.hid
import Foundation
let args = CommandLine.arguments.dropFirst().map{ UInt8($0, radix:16)! }
let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 0x19f5, kIOHIDPrimaryUsagePageKey: 0xFF60] as CFDictionary)
IOHIDManagerOpen(m, 0)
guard let devs = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, let d = devs.first else { print("no dev"); exit(1) }
print("open", IOHIDDeviceOpen(d, 0))
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
// Other processes (e.g. kvm-switch) may talk to the same interface; only accept the
// reply whose leading bytes echo this request, then exit.
let echo = Array(args.prefix(args.first == 0x01 || args.first == 0x0b ? 1 : min(args.count, 4)))
IOHIDDeviceRegisterInputReportCallback(d, buf, 32, { _, _, _, _, _, r, len in
  let isReply = (0..<echo.count).allSatisfy { r[$0] == echo[$0] } || r[0] == 0xff
  guard isReply else { return }
  print("resp", (0..<len).map{ String(format:"%02x", r[$0]) }.joined(separator:" "))
  exit(0) }, nil)
IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
var out = [UInt8](repeating: 0, count: 32); for (i,b) in args.enumerated() { out[i] = b }
print("send", IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0, out, 32))
RunLoop.main.run(until: Date().addingTimeInterval(2))
