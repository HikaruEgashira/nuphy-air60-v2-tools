// snap: board-wide cursor control.
//   F13  pad: each letter key moves the cursor by its offset from the middle of the
//        keyboard's letter block; the step shrinks per press. Space clicks, Esc exits.
//   F14  element hints: labels every interactive element in every visible window.
//   F15  window hints: labels every on-screen window.
// Type a label to move the cursor there; type its last letter with Shift to also
// click (elements) or raise (windows). Esc or any non-label key cancels.
// Needs Accessibility permission.
import AppKit
import ApplicationServices
import Carbon
setvbuf(stdout, nil, _IONBF, 0)

// Dvorak home row, so labels stay under the fingers.
let alphabet = Array("aoeuidhtns")

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

func windowTargets() -> [Target] {
  let wins = onScreenWindows()
  return wins.enumerated().compactMap { i, w in
    visible(CGRect(x: w.rect.midX - 1, y: w.rect.minY + 12, width: 2, height: 2), behind: wins[..<i].map(\.rect)) || i == 0
      ? Target(rect: w.rect, element: nil, pid: w.pid) : Target(rect: w.rect, element: nil, pid: w.pid)
  }
}

// MARK: Labels

/// Prefix-free labels of equal length over `alphabet`.
func labels(_ n: Int) -> [String] {
  guard n > 0 else { return [] }
  var len = 1
  while Int(pow(Double(alphabet.count), Double(len))) < n { len += 1 }
  return (0..<n).map { i in
    var x = i, s = ""
    for _ in 0..<len { s = String(alphabet[x % alphabet.count]) + s; x /= alphabet.count }
    return s
  }
}

// MARK: Actions

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

func raise(_ t: Target) {
  NSRunningApplication(processIdentifier: t.pid)?.activate()
  let app = AXUIElementCreateApplication(t.pid)
  if let wins: [AXUIElement] = attr(app, kAXWindowsAttribute),
     let w = wins.first(where: { frame($0).map { abs($0.minX - t.rect.minX) < 2 && abs($0.minY - t.rect.minY) < 2 } ?? false }) {
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
  }
}

// MARK: Overlay

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }

final class HintView: NSView {
  var hints: [(String, CGRect)] = []
  var typed = ""
  override var isFlipped: Bool { true }
  override func draw(_ dirty: NSRect) {
    NSColor.black.withAlphaComponent(0.12).setFill(); bounds.fill()
    let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    for (label, r) in hints where label.hasPrefix(typed) {
      let s = NSMutableAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.black])
      s.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: NSRange(location: 0, length: typed.count))
      let size = s.size()
      let box = CGRect(x: r.midX - size.width / 2 - 4, y: r.midY - size.height / 2 - 2, width: size.width + 8, height: size.height + 4)
      NSColor.systemYellow.setFill(); NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
      NSColor.black.withAlphaComponent(0.5).setStroke(); NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).stroke()
      s.draw(at: CGPoint(x: box.minX + 4, y: box.minY + 2))
    }
  }
}

final class Session {
  static var current: Session?
  let targets: [Target]; let labels: [String]; let windowMode: Bool
  var windows: [(KeyWindow, HintView)] = []
  var typed = ""
  var monitor: Any?
  let previous = NSWorkspace.shared.frontmostApplication

  init(windowMode: Bool) {
    self.windowMode = windowMode
    targets = windowMode ? windowTargets() : elementTargets()
    labels = snap.labels(targets.count)
  }

  func show() {
    guard !targets.isEmpty else { return }
    // Quartz coordinates are top-left of the primary screen; AppKit is bottom-left.
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    for screen in NSScreen.screens {
      let f = screen.frame
      let w = KeyWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false)
      w.level = .screenSaver; w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
      w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      let v = HintView(frame: CGRect(origin: .zero, size: f.size))
      let top = primaryH - f.maxY
      v.hints = zip(labels, targets).compactMap { l, t in
        let r = t.rect.offsetBy(dx: -f.minX, dy: -top)
        return v.bounds.contains(CGPoint(x: r.midX, y: r.midY)) ? (l, windowMode ? CGRect(x: r.midX - 1, y: r.minY + 24, width: 2, height: 2) : r) : nil
      }
      w.contentView = v
      w.orderFrontRegardless()
      windows.append((w, v))
    }
    NSApp.activate(ignoringOtherApps: true)
    windows.first?.0.makeKey()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e); return nil }
    Session.current = self
  }

  func key(_ e: NSEvent) {
    guard e.keyCode != UInt16(kVK_Escape), let ch = e.charactersIgnoringModifiers?.lowercased(), ch.count == 1,
          alphabet.contains(Character(ch)) else { return finish(nil, act: false) }
    typed += ch
    let matches = labels.indices.filter { labels[$0].hasPrefix(typed) }
    if matches.isEmpty { return finish(nil, act: false) }
    if matches.count == 1, labels[matches[0]] == typed { return finish(targets[matches[0]], act: e.modifierFlags.contains(.shift)) }
    for (_, v) in windows { v.typed = typed; v.needsDisplay = true }
  }

  func finish(_ t: Target?, act: Bool) {
    if let m = monitor { NSEvent.removeMonitor(m) }
    windows.forEach { $0.0.orderOut(nil) }
    windows = []
    Session.current = nil
    guard let t else { previous?.activate(); return }
    if windowMode {
      raise(t)
      warp(CGPoint(x: t.rect.midX, y: t.rect.midY))
    } else {
      previous?.activate()
      let p = center(t.rect)
      warp(p)
      if act { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { click(p) } }
    }
  }
}


// MARK: Pad

/// Dvorak letter block, top to bottom: each character sits where its key is.
let padRows = [Array("',.pyfgcrl"), Array("aoeuidhtns"), Array(";qjkxbmwvz")]

/// Offset of a key from the middle of the block: x in -1...1 (columns), y in -1...1 (rows).
func padOffset(_ r: Int, _ c: Int) -> CGVector { CGVector(dx: (CGFloat(c) - 4.5) / 4.5, dy: CGFloat(r - 1)) }

final class PadView: NSView {
  var origin = CGPoint.zero      // cursor, view coordinates
  var span = CGSize.zero
  override var isFlipped: Bool { true }
  override func draw(_ dirty: NSRect) {
    NSColor.black.withAlphaComponent(0.08).setFill(); bounds.fill()
    let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .heavy)
    NSColor.systemOrange.setFill()
    NSBezierPath(ovalIn: CGRect(x: origin.x - 5, y: origin.y - 5, width: 10, height: 10)).fill()
    for (r, row) in padRows.enumerated() {
      for (c, k) in row.enumerated() {
        let o = padOffset(r, c)
        // Same clamp as the move itself, so every key stays visible near edges.
        let p = CGPoint(x: min(max(origin.x + o.dx * span.width, 10), bounds.maxX - 10),
                        y: min(max(origin.y + o.dy * span.height, 10), bounds.maxY - 10))
        let s = NSAttributedString(string: String(k), attributes: [.font: font, .foregroundColor: NSColor.black])
        let size = s.size()
        let box = CGRect(x: p.x - size.width / 2 - 4, y: p.y - size.height / 2 - 1, width: size.width + 8, height: size.height + 2)
        (r == 1 ? NSColor.systemYellow : NSColor.systemYellow.withAlphaComponent(0.75)).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        s.draw(at: CGPoint(x: box.minX + 4, y: box.minY + 1))
      }
    }
  }
}

/// Relative cursor pad: each key moves the cursor by its offset from the middle of the
/// letter block, and the step shrinks after every press (coarse, then fine).
final class PadSession {
  static var current: PadSession?
  var window: KeyWindow?
  var view: PadView?
  var pos = CGPoint.zero          // Quartz global
  var span = CGSize.zero
  var screen = CGRect.zero        // Quartz global bounds of the current screen
  var appKitFrame = CGRect.zero
  var monitor: Any?
  let previous = NSWorkspace.shared.frontmostApplication

  func show() {
    pos = CGEvent(source: nil)?.location ?? .zero
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    let mouse = NSEvent.mouseLocation
    let s = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
    appKitFrame = s.frame
    screen = CGRect(x: s.frame.minX, y: primaryH - s.frame.maxY, width: s.frame.width, height: s.frame.height)
    span = CGSize(width: screen.width * 0.45, height: screen.height * 0.35)
    let w = KeyWindow(contentRect: appKitFrame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .screenSaver; w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
    w.ignoresMouseEvents = true
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let v = PadView(frame: CGRect(origin: .zero, size: appKitFrame.size))
    w.contentView = v
    window = w; view = v
    redraw()
    w.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    w.makeKey()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e); return nil }
    PadSession.current = self
  }

  func redraw() {
    view?.origin = CGPoint(x: pos.x - screen.minX, y: pos.y - screen.minY)
    view?.span = span
    view?.needsDisplay = true
  }

  func key(_ e: NSEvent) {
    if e.keyCode == UInt16(kVK_Space) || e.keyCode == UInt16(kVK_Return) { return finish(click: true) }
    guard e.keyCode != UInt16(kVK_Escape), let ch = e.charactersIgnoringModifiers?.lowercased().first,
          let r = padRows.firstIndex(where: { $0.contains(ch) }), let c = padRows[r].firstIndex(of: ch) else { return finish(click: false) }
    let o = padOffset(r, c)
    pos = CGPoint(x: min(max(pos.x + o.dx * span.width, screen.minX + 1), screen.maxX - 1),
                  y: min(max(pos.y + o.dy * span.height, screen.minY + 1), screen.maxY - 1))
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

func start(windowMode: Bool) {
  if let s = Session.current { s.finish(nil, act: false); return }
  Session(windowMode: windowMode).show()
}

func startPad() {
  if let p = PadSession.current { p.finish(click: false); return }
  PadSession().show()
}

// MARK: Hotkeys

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "count" {
  print("trusted", AXIsProcessTrusted(), "windows", windowTargets().count)
  let t0 = Date(); let n = elementTargets().count
  print("elements", n, "in", Int(Date().timeIntervalSince(t0) * 1000), "ms; labels", labels(n).first ?? "-", "…", labels(n).last ?? "-")
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
InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
  var hk = EventHotKeyID()
  GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hk)
  DispatchQueue.main.async {
    switch hk.id { case 0: startPad(); case 1: start(windowMode: false); default: start(windowMode: true) }
  }
  return noErr
}, 1, &spec, nil, nil)
for (id, key) in [(UInt32(0), kVK_F13), (1, kVK_F14), (2, kVK_F15)] {
  var ref: EventHotKeyRef?
  let st = RegisterEventHotKey(UInt32(key), 0, EventHotKeyID(signature: 0x534E4150, id: id), GetApplicationEventTarget(), 0, &ref)
  if st != noErr { print("hotkey", id, "failed", st) }
}
print("snap ready; accessibility trusted:", AXIsProcessTrusted())
app.run()
