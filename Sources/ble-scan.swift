import CoreBluetooth
import Foundation
class S: NSObject, CBCentralManagerDelegate {
  var m: CBCentralManager!
  var seen = Set<UUID>()
  override init(){ super.init(); m = CBCentralManager(delegate: self, queue: nil) }
  func centralManagerDidUpdateState(_ c: CBCentralManager) {
    print("state", c.state.rawValue)
    if c.state == .poweredOn {
      for p in c.retrieveConnectedPeripherals(withServices: [CBUUID(string:"1812")]) { print("CONNECTED-HID", p.name ?? "?", p.identifier) }
      c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
  }
  func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData a: [String: Any], rssi: NSNumber) {
    if seen.insert(p.identifier).inserted {
      let n = p.name ?? (a[CBAdvertisementDataLocalNameKey] as? String) ?? "-"
      print(n, rssi, p.identifier, (a[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [], a[CBAdvertisementDataIsConnectable] ?? "")
    }
  }
}
let s = S()
RunLoop.main.run(until: Date().addingTimeInterval(15))
