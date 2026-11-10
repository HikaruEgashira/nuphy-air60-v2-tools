// DDC/CI over IOAVService (Apple Silicon external displays).
import Foundation
import IOKit

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ a: CFAllocator?, _ s: io_service_t) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ s: CFTypeRef, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ s: CFTypeRef, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

func services() -> [CFTypeRef] {
  var out: [CFTypeRef] = []
  var it = io_iterator_t()
  guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return [] }
  while case let s = IOIteratorNext(it), s != 0 {
    let loc = IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    if loc == "External", let av = IOAVServiceCreateWithService(kCFAllocatorDefault, s)?.takeRetainedValue() { out.append(av) }
    IOObjectRelease(s)
  }
  return out
}
func checksum(_ seed: UInt8, _ b: [UInt8]) -> UInt8 { b.reduce(seed, ^) }
func write(_ av: CFTypeRef, _ payload: [UInt8]) -> IOReturn {
  var pkt: [UInt8] = [0x80 | UInt8(payload.count)] + payload
  pkt.append(checksum(0x6E ^ 0x51, pkt))
  var r: IOReturn = 0
  for _ in 0..<2 { r = IOAVServiceWriteI2C(av, 0x37, 0x51, &pkt, UInt32(pkt.count)); usleep(10_000) }
  return r
}

func ddcSet(_ vcp: UInt8, _ v: UInt16) -> [IOReturn] { services().map { write($0, [0x03, vcp, UInt8(v >> 8), UInt8(v & 0xff)]) } }
func ddcGet(_ av: CFTypeRef, _ vcp: UInt8) -> (IOReturn, [UInt8]) {
  _ = write(av, [0x01, vcp]); usleep(50_000)
  var buf = [UInt8](repeating: 0, count: 12)
  let r = IOAVServiceReadI2C(av, 0x37, 0x51, &buf, 12)
  return (r, buf)
}
/// Current value of a VCP feature, or nil when the reply is malformed or fails its checksum.
func ddcRead(_ av: CFTypeRef, _ vcp: UInt8) -> UInt16? {
  let (r, b) = ddcGet(av, vcp)
  guard r == 0, b[0] == 0x6E, b[1] == 0x88, b[2] == 0x02, b[3] == 0x00, b[4] == vcp,
        checksum(0x50, Array(b[0..<10])) == b[10] else { return nil }
  return UInt16(b[8]) << 8 | UInt16(b[9])
}
/// Sets the display input and retries until it reads back (DELL echoes the code in both bytes).
func ddcSetInput(_ v: UInt16, attempts: Int = 6) -> Bool {
  for _ in 0..<attempts {
    _ = ddcSet(0x60, v)
    sleep(1)
    if let av = services().first, let cur = ddcRead(av, 0x60), cur & 0xff == v & 0xff { return true }
  }
  return false
}
