import CoreBluetooth
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
let dir = CommandLine.arguments[1]
let initPkt = try! Data(contentsOf: URL(fileURLWithPath: dir + "/app.dat"))
let fw = try! Data(contentsOf: URL(fileURLWithPath: dir + "/app.bin"))
func crc32(_ d: Data) -> UInt32 { var c: UInt32 = 0xFFFFFFFF; for b in d { c ^= UInt32(b); for _ in 0..<8 { c = (c >> 1) ^ (0xEDB88320 & (0 &- (c & 1))) } }; return ~c }
func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v>>8)&0xff), UInt8((v>>16)&0xff), UInt8(v>>24)] }
class T: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  var m: CBCentralManager!; var p: CBPeripheral?; var cp: CBCharacteristic?; var pk: CBCharacteristic?
  var cont: (([UInt8]) -> Void)?
  var phase = 0; var obj = Data(); var objOff = 0; var maxSize = 0; var sent = 0
  override init(){ super.init(); m = CBCentralManager(delegate: self, queue: nil) }
  func centralManagerDidUpdateState(_ c: CBCentralManager) { if c.state == .poweredOn { print("scanning for DfuTarg"); c.scanForPeripherals(withServices: nil) } }
  func centralManager(_ c: CBCentralManager, didDiscover x: CBPeripheral, advertisementData a: [String: Any], rssi: NSNumber) {
    let n = x.name ?? (a[CBAdvertisementDataLocalNameKey] as? String) ?? ""
    let su = (a[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
    guard p == nil, n.contains("DfuTarg") || su.contains(CBUUID(string:"FE59")) else { return }
    c.stopScan(); p = x; x.delegate = self; print("found", n, x.identifier, rssi); c.connect(x)
  }
  func centralManager(_ c: CBCentralManager, didConnect x: CBPeripheral) { print("connected"); x.discoverServices([CBUUID(string:"FE59")]) }
  func centralManager(_ c: CBCentralManager, didFailToConnect x: CBPeripheral, error: Error?) { print("fail", error ?? ""); exit(2) }
  func centralManager(_ c: CBCentralManager, didDisconnectPeripheral x: CBPeripheral, error: Error?) { print("disconnected", error ?? "", "phase", phase); exit(phase == 9 ? 0 : 3) }
  func peripheral(_ x: CBPeripheral, didDiscoverServices e: Error?) { for s in x.services ?? [] { x.discoverCharacteristics(nil, for: s) } }
  func peripheral(_ x: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error e: Error?) {
    for ch in s.characteristics ?? [] { if ch.uuid == CBUUID(string:"8EC90001-F315-4F60-9FB8-838830DAEA50") { cp = ch }; if ch.uuid == CBUUID(string:"8EC90002-F315-4F60-9FB8-838830DAEA50") { pk = ch } }
    guard let cp = cp, pk != nil else { print("no dfu chars", s.characteristics ?? []); exit(4) }
    x.setNotifyValue(true, for: cp)
  }
  func peripheral(_ x: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error e: Error?) {
    print("notify on", e ?? "ok"); print("mtu", x.maximumWriteValueLength(for: .withoutResponse))
    cmd([0x02, 0, 0]) { _ in self.startObject(type: 1, data: initPkt) }
  }
  func cmd(_ b: [UInt8], _ k: @escaping ([UInt8]) -> Void) { cont = k; p!.writeValue(Data(b), for: cp!, type: .withResponse) }
  func peripheral(_ x: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error e: Error?) {
    let r = [UInt8](ch.value ?? Data())
    guard r.count >= 3, r[0] == 0x60, r[2] == 0x01 else { print("ERR resp", r.map{String(format:"%02x",$0)}); exit(5) }
    let k = cont; cont = nil; k?(Array(r[3...]))
  }
  func peripheral(_ x: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error e: Error?) { if let e = e { print("write err", e); exit(6) } }
  var type: UInt8 = 1; var data = Data(); var base = 0
  func startObject(type t: UInt8, data d: Data) {
    type = t; data = d
    cmd([0x06, t]) { r in
      self.maxSize = Int(r[0]) | Int(r[1])<<8 | Int(r[2])<<16 | Int(r[3])<<24
      print("select type", t, "max", self.maxSize); self.base = 0; self.nextChunk()
    }
  }
  func nextChunk() {
    if base >= data.count {
      if type == 1 { print("init done"); startObject(type: 2, data: fw) } else { phase = 9; print("FIRMWARE DONE") }
      return
    }
    let end = min(base + maxSize, data.count); let chunk = data.subdata(in: base..<end)
    cmd([0x01, type] + le32(UInt32(chunk.count))) { _ in
      let mtu = self.p!.maximumWriteValueLength(for: .withoutResponse)
      var o = 0
      func pump() {
        while o < chunk.count && self.p!.canSendWriteWithoutResponse {
          let e = min(o + mtu, chunk.count); self.p!.writeValue(chunk.subdata(in: o..<e), for: self.pk!, type: .withoutResponse); o = e
        }
        if o < chunk.count { DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { pump() }; return }
        self.cmd([0x03]) { r in
          let off = Int(r[0]) | Int(r[1])<<8 | Int(r[2])<<16 | Int(r[3])<<24
          let crc = UInt32(r[4]) | UInt32(r[5])<<8 | UInt32(r[6])<<16 | UInt32(r[7])<<24
          let exp = crc32(self.data.subdata(in: 0..<end))
          guard off == end, crc == exp else { print("CRC mismatch", off, end, crc, exp); exit(7) }
          self.cmd([0x04]) { _ in print("obj ok", end, "/", self.data.count); self.base = end; self.nextChunk() }
        }
      }
      pump()
    }
  }
}
let t = T()
RunLoop.main.run(until: Date().addingTimeInterval(900))
print("timeout"); exit(8)
