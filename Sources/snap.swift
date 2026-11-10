// snap: Caps-tap cursor pad (F13). Outlines every element and window; each letter key
// moves the cursor by its offset from the middle of the letter block and sticks to the
// nearest element. Space/Enter click, Shift+key moves and clicks, Esc exits.
// Needs Accessibility permission.
import AppKit
import ApplicationServices
import Carbon
setvbuf(stdout, nil, _IONBF, 0)


struct Target { let rect: CGRect; let element: AXUIElement?; let pid: pid_t }

// MARK: Accessibility

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

let interactiveRoles: Set<String> = [
  "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXSearchField", "AXCheckBox", "AXRadioButton",
  "AXPopUpButton", "AXMenuButton", "AXComboBox", "AXSlider", "AXTab", "AXDisclosureTriangle",
  "AXCell", "AXIncrementor", "AXColorWell", "AXSegmentedControl", "AXMenuBarItem", "AXDockItem",
]

struct OnScreenWindow { let rect: CGRect; let pid: pid_t; let number: Int }

/// Layer-0 windows front to back, as Quartz sees them.
func onScreenWindows() -> [OnScreenWindow] {
  guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
  return list.compactMap { w in
    guard (w[kCGWindowLayer as String] as? Int) == 0,
          let b = w[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: b), r.width > 80, r.height > 60,
          let pid = w[kCGWindowOwnerPID as String] as? pid_t,
          let n = w[kCGWindowNumber as String] as? Int else { return nil }
    return OnScreenWindow(rect: r, pid: pid, number: n)
  }
}

/// Visible part of `r`: drops areas covered by windows in front of it.
func visible(_ r: CGRect, behind front: [CGRect]) -> Bool {
  let c = CGPoint(x: r.midX, y: r.midY)
  return !front.contains { $0.contains(c) }
}

func elementTargets() -> [Target] {
  let wins = onScreenWindows()
  let pids = Array(Set(wins.map(\.pid)))
  var out: [Target] = []
  let deadline = Date().addingTimeInterval(0.8)
  for pid in pids {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.2)
    // Electron and Chromium only build their accessibility tree when asked.
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    guard let axWins: [AXUIElement] = attr(app, kAXWindowsAttribute) else { continue }
    for w in axWins {
      guard let wf = frame(w) else { continue }
      // Occluders: on-screen windows in front of this one.
      guard let idx = wins.firstIndex(where: { $0.pid == pid && abs($0.rect.minX - wf.minX) < 2 && abs($0.rect.minY - wf.minY) < 2 }) else { continue }
      let front = wins[..<idx].map(\.rect)
      var queue: [AXUIElement] = [w]
      var visited = 0
      while !queue.isEmpty, visited < 8000, Date() < deadline {
        let e = queue.removeFirst(); visited += 1
        if let role: String = attr(e, kAXRoleAttribute), interactiveRoles.contains(role),
           let f = frame(e), f.width >= 6, f.height >= 6 {
          let clipped = f.intersection(wf)
          if !clipped.isNull, visible(clipped, behind: front) { out.append(Target(rect: clipped, element: e, pid: pid)) }
        }
        if let kids: [AXUIElement] = attr(e, kAXChildrenAttribute) ?? attr(e, kAXVisibleChildrenAttribute) {
          queue.append(contentsOf: kids)
        }
      }
    }
  }
  // Collapse near-duplicates (nested elements with the same center).
  var seen = Set<String>()
  return out.filter { seen.insert("\(Int($0.rect.midX) / 8),\(Int($0.rect.midY) / 8)").inserted }
}



func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

func warp(_ p: CGPoint) {
  CGWarpMouseCursorPosition(p)
  CGAssociateMouseAndMouseCursorPosition(1)
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func click(_ p: CGPoint) {
  for t: CGEventType in [.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
  }
}

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }

// MARK: Pad

/// Dvorak letter block, top to bottom: each character sits where its key is.
let padRows = [Array("',.pyfgcrl"), Array("aoeuidhtns"), Array(";qjkxbmwvz")]

/// Offset of a key from the middle of the block: x in -1...1, y in -1...1.
func padOffset(_ r: Int, _ c: Int) -> CGVector { CGVector(dx: (CGFloat(c) - 4.5) / 4.5, dy: CGFloat(r - 1)) }

final class PadView: NSView {
  var origin = CGPoint.zero
  var elements: [CGRect] = []
  var windows: [CGRect] = []
  var landings: [(Character, CGPoint)] = []
  override var isFlipped: Bool { true }
  override func draw(_ dirty: NSRect) {
    NSColor.black.withAlphaComponent(0.08).setFill(); bounds.fill()
    NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
    for w in windows { let p = NSBezierPath(rect: w.insetBy(dx: 1, dy: 1)); p.lineWidth = 3; p.stroke() }
    NSColor.systemTeal.withAlphaComponent(0.7).setStroke()
    for e in elements { NSBezierPath(roundedRect: e, xRadius: 3, yRadius: 3).stroke() }
    NSColor.systemOrange.setFill()
    NSBezierPath(ovalIn: CGRect(x: origin.x - 6, y: origin.y - 6, width: 12, height: 12)).fill()
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .heavy)
    for (k, p) in landings {
      let s = NSAttributedString(string: String(k), attributes: [.font: font, .foregroundColor: NSColor.black])
      let size = s.size()
      let box = CGRect(x: p.x - size.width / 2 - 4, y: p.y - size.height / 2 - 1, width: size.width + 8, height: size.height + 2)
      NSColor.systemYellow.setFill(); NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
      s.draw(at: CGPoint(x: box.minX + 4, y: box.minY + 1))
    }
  }
}

/// Caps tap: outlines every element and window, then each letter key moves the cursor
/// by its offset from the middle of the letter block and sticks to the nearest element
/// around the landing spot. The step shrinks per press.
final class PadSession {
  static var current: PadSession?
  var window: KeyWindow?
  var view: PadView?
  var pos = CGPoint.zero
  var span = CGSize.zero
  var screen = CGRect.zero
  var elements: [CGRect] = []
  var windows: [CGRect] = []
  var monitor: Any?
  let previous = NSWorkspace.shared.frontmostApplication

  func show() {
    pos = CGEvent(source: nil)?.location ?? .zero
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    let mouse = NSEvent.mouseLocation
    let s = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
    screen = CGRect(x: s.frame.minX, y: primaryH - s.frame.maxY, width: s.frame.width, height: s.frame.height)
    span = CGSize(width: screen.width * 0.45, height: screen.height * 0.35)
    elements = elementTargets().map(\.rect).filter { screen.intersects($0) }
    windows = onScreenWindows().map(\.rect).filter { screen.intersects($0) }
    let w = KeyWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .screenSaver; w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
    w.ignoresMouseEvents = true
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let v = PadView(frame: CGRect(origin: .zero, size: s.frame.size))
    w.contentView = v
    window = w; view = v
    redraw()
    w.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    w.makeKey()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e); return nil }
    PadSession.current = self
  }

  /// Where a key would land: the raw offset, pulled onto the nearest element in reach.
  func landing(_ r: Int, _ c: Int) -> CGPoint {
    let o = padOffset(r, c)
    let raw = CGPoint(x: min(max(pos.x + o.dx * span.width, screen.minX + 1), screen.maxX - 1),
                      y: min(max(pos.y + o.dy * span.height, screen.minY + 1), screen.maxY - 1))
    let reach = max(min(span.width, span.height) * 0.5, 12)
    let near = elements.map { center($0) }.min { hypot($0.x - raw.x, $0.y - raw.y) < hypot($1.x - raw.x, $1.y - raw.y) }
    if let n = near, hypot(n.x - raw.x, n.y - raw.y) <= reach, n != pos { return n }
    return raw
  }

  func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - screen.minX, y: p.y - screen.minY) }

  func redraw() {
    guard let v = view else { return }
    v.origin = local(pos)
    v.elements = elements.map { $0.offsetBy(dx: -screen.minX, dy: -screen.minY) }
    v.windows = windows.map { $0.offsetBy(dx: -screen.minX, dy: -screen.minY) }
    v.landings = padRows.enumerated().flatMap { r, row in row.enumerated().map { c, k in (k, local(landing(r, c))) } }
    v.needsDisplay = true
  }

  func key(_ e: NSEvent) {
    if e.keyCode == UInt16(kVK_Space) || e.keyCode == UInt16(kVK_Return) { return finish(click: true) }
    guard e.keyCode != UInt16(kVK_Escape), let ch = e.charactersIgnoringModifiers?.lowercased().first,
          let r = padRows.firstIndex(where: { $0.contains(ch) }), let c = padRows[r].firstIndex(of: ch) else { return finish(click: false) }
    pos = landing(r, c)
    warp(pos)
    if e.modifierFlags.contains(.shift) { return finish(click: true) }
    span = CGSize(width: max(span.width * 0.45, 8), height: max(span.height * 0.45, 6))
    redraw()
  }

  func finish(click doClick: Bool) {
    if let m = monitor { NSEvent.removeMonitor(m) }
    window?.orderOut(nil); window = nil
    PadSession.current = nil
    previous?.activate()
    let p = pos
    if doClick { DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { click(p) } }
  }
}

func startPad() {
  if let p = PadSession.current { p.finish(click: false); return }
  PadSession().show()
}

// MARK: Hotkeys

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "count" {
  print("trusted", AXIsProcessTrusted(), "windows", onScreenWindows().count)
  let t0 = Date(); let n = elementTargets().count
  print("elements", n, "in", Int(Date().timeIntervalSince(t0) * 1000), "ms")
  exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "show-pad" {
  DispatchQueue.main.async { startPad() }
  DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
  app.run()
}
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
  DispatchQueue.main.async { startPad() }
  return noErr
}, 1, &spec, nil, nil)
var ref: EventHotKeyRef?
let st = RegisterEventHotKey(UInt32(kVK_F13), 0, EventHotKeyID(signature: 0x534E4150, id: 0), GetApplicationEventTarget(), 0, &ref)
if st != noErr { print("hotkey failed", st) }
print("snap ready; accessibility trusted:", AXIsProcessTrusted())
app.run()
