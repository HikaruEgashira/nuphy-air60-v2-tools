// snap: move the mouse cursor to the nearest window or UI element in a direction.
// Global hotkeys (sent by the Caps layer): F13-F16 element left/down/up/right,
// Shift+F13-F16 window left/down/up/right (macOS has no F21+). Element snap needs Accessibility permission.
import AppKit
import ApplicationServices
import Carbon
setvbuf(stdout, nil, _IONBF, 0)

enum Dir: UInt32 { case left = 0, down, up, right }

func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

/// Picks the target whose center lies in `dir` from `p`, preferring small
/// off-axis distance. Targets containing the cursor are skipped.
func pick(_ rects: [CGRect], from p: CGPoint, _ dir: Dir) -> CGRect? {
  var best: (CGRect, CGFloat)?
  for r in rects where r.width >= 4 && r.height >= 4 && !r.contains(p) {
    let c = CGPoint(x: r.midX, y: r.midY)
    let dx = c.x - p.x, dy = c.y - p.y
    let (along, across): (CGFloat, CGFloat)
    switch dir {
    case .left: (along, across) = (-dx, dy)
    case .right: (along, across) = (dx, dy)
    case .up: (along, across) = (-dy, dx)
    case .down: (along, across) = (dy, dx)
    }
    guard along > 2, abs(across) <= along * 2 else { continue }
    let score = along + 2 * abs(across)
    if best == nil || score < best!.1 { best = (r, score) }
  }
  return best?.0
}

func warp(_ r: CGRect) {
  let c = CGPoint(x: r.midX, y: r.midY)
  CGWarpMouseCursorPosition(c)
  CGAssociateMouseAndMouseCursorPosition(1)
  // Synthesize a move so hover states and apps see the new position.
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func windowRects() -> [CGRect] {
  guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
  return list.compactMap { w in
    guard (w[kCGWindowLayer as String] as? Int) == 0,
          let b = w[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: b), r.width > 80, r.height > 60 else { return nil }
    return r
  }
}

let interactiveRoles: Set<String> = [
  "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXSearchField", "AXCheckBox", "AXRadioButton",
  "AXPopUpButton", "AXMenuButton", "AXComboBox", "AXSlider", "AXTab", "AXMenuBarItem", "AXDisclosureTriangle",
  "AXCell", "AXRow", "AXImage", "AXStaticText", "AXIncrementor", "AXColorWell", "AXSegmentedControl",
]

func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
  var v: CFTypeRef?
  guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
  return v as? T
}

func frame(_ e: AXUIElement) -> CGRect? {
  var pos = CGPoint.zero, size = CGSize.zero
  guard let pv: AXValue = attr(e, kAXPositionAttribute), let sv: AXValue = attr(e, kAXSizeAttribute),
        AXValueGetValue(pv, .cgPoint, &pos), AXValueGetValue(sv, .cgSize, &size) else { return nil }
  return CGRect(origin: pos, size: size)
}

/// Interactive elements of the window under the cursor (or the frontmost app's focused window).
func elementRects(near p: CGPoint) -> [CGRect] {
  let system = AXUIElementCreateSystemWide()
  var hit: AXUIElement?
  var root: AXUIElement?
  if AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &hit) == .success, let h = hit {
    root = attr(h, kAXWindowAttribute) ?? h
  }
  if root == nil, let app = NSWorkspace.shared.frontmostApplication {
    root = attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute)
  }
  guard let start = root, let bounds = frame(start) else { return [] }
  var out: [CGRect] = []
  var queue: [AXUIElement] = [start]
  var visited = 0
  let deadline = Date().addingTimeInterval(0.25)
  while !queue.isEmpty, visited < 4000, Date() < deadline {
    let e = queue.removeFirst(); visited += 1
    if let role: String = attr(e, kAXRoleAttribute), interactiveRoles.contains(role),
       let f = frame(e), bounds.intersects(f) {
      out.append(f.intersection(bounds))
    }
    if let kids: [AXUIElement] = attr(e, kAXVisibleChildrenAttribute) ?? attr(e, kAXChildrenAttribute) {
      queue.append(contentsOf: kids)
    }
  }
  return out
}

func handle(_ id: UInt32) {
  let p = cursor()
  let element = id < 4
  guard let dir = Dir(rawValue: id % 4) else { return }
  let rects = element ? elementRects(near: p) : windowRects()
  if let r = pick(rects, from: p, dir) { warp(r) }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "test", let id = UInt32(CommandLine.arguments[2]) {
  let before = cursor(); handle(id); print("trusted", AXIsProcessTrusted(), "from", before, "to", cursor()); exit(0)
}
let fkeys = [kVK_F13, kVK_F14, kVK_F15, kVK_F16]
let bindings: [(id: UInt32, key: Int, mods: Int)] =
  fkeys.enumerated().map { (UInt32($0.offset), $0.element, 0) } +
  fkeys.enumerated().map { (UInt32(4 + $0.offset), $0.element, shiftKey) }
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
  var hk = EventHotKeyID()
  GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hk)
  handle(hk.id)
  return noErr
}, 1, &spec, nil, nil)
for b in bindings {
  var ref: EventHotKeyRef?
  let st = RegisterEventHotKey(UInt32(b.key), UInt32(b.mods), EventHotKeyID(signature: 0x534E4150 /* SNAP */, id: b.id), GetApplicationEventTarget(), 0, &ref)
  if st != noErr { print("hotkey", b.id, "failed", st) }
}
print("snap ready; accessibility trusted:", AXIsProcessTrusted())
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
