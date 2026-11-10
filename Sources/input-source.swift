// input-source: list/enable/select/disable macOS keyboard input sources.
// usage: input-source list | input-source enable|select|disable <source-id>
import Carbon
import Foundation
let a = CommandLine.arguments
let all = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
func prop(_ s: TISInputSource, _ k: CFString) -> String? {
  guard let p = TISGetInputSourceProperty(s, k) else { return nil }
  return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? String
}
func enabled(_ s: TISInputSource) -> Bool {
  guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceIsEnabled) else { return false }
  return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
}
if a.count < 2 || a[1] == "list" {
  for s in all where enabled(s) { print(prop(s, kTISPropertyInputSourceID) ?? "?") }
  exit(0)
}
guard a.count >= 3, let s = all.first(where: { prop($0, kTISPropertyInputSourceID) == a[2] }) else { print("not found"); exit(1) }
let r: OSStatus
switch a[1] {
case "enable": r = TISEnableInputSource(s)
case "select": r = TISSelectInputSource(s)
case "disable": r = TISDisableInputSource(s)
default: print("unknown command"); exit(64)
}
print(a[1], a[2], r)
exit(r == noErr ? 0 : 1)
