// ddc: read/write a DDC/CI VCP feature on external displays.
// usage: ddc get <vcp-hex> | ddc set <vcp-hex> <value>
import Foundation
let a = CommandLine.arguments
guard a.count >= 3, let vcp = UInt8(a[2], radix: 16) else { print("usage: ddc get <vcp-hex> | ddc set <vcp-hex> <value>"); exit(64) }
let avs = services()
guard !avs.isEmpty else { print("no external display"); exit(1) }
if a[1] == "set", a.count >= 4, let v = UInt16(a[3]) {
  print("set 0x\(String(vcp, radix: 16)) = \(v):", ddcSet(vcp, v))
} else {
  for (i, av) in avs.enumerated() {
    let (r, buf) = ddcGet(av, vcp)
    print("display \(i) 0x\(String(vcp, radix: 16)): ret=\(r) current=\(Int(buf[8]) << 8 | Int(buf[9])) max=\(Int(buf[6]) << 8 | Int(buf[7]))")
  }
}
