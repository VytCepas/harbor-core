// access-desktop-helper.swift — harbor desktop's helper app (D-95, harbor#1440).
// One process with its own identity, so macOS attributes Accessibility, Screen Recording and Automation to it.
// Serves newline-delimited JSON on a Unix socket; the MCP server and `harbor desktop` are its only clients.
import AppKit
import ApplicationServices
import ScreenCaptureKit
import OSAKit
import UniformTypeIdentifiers

let version = "1"
struct Fail: Error { let msg: String }
// A refusal opens with [desktop:<rule>], a row of standards/naming/controls.tsv (emitted column); the lint's census
// reads the stamps from this file, so a new refusal without a row is red (name.control-unregistered, harbor#1599).

// ── policy: allow-list, hard deny, live-change words (one enforcement point for every client) ──
var allowed: Set<String> = []
var words: [String] = []
var hosts: [String] = []
var missing: [String] = []  // policy files that could not be read: each reads as empty (fails closed), doctor names them
let hardDeny: Set<String> = [  // secrets and the machine's own controls: never, whatever the list says
  "com.apple.keychainaccess", "com.apple.Passwords", "com.apple.systempreferences", "com.apple.SecurityAgent",
  "com.apple.Terminal", "com.googlecode.iterm2", "com.1password.1password", "com.agilebits.onepassword7",
  "com.bitwarden.desktop", "com.apple.ScreenSharing", "com.apple.Console"]
// The same apps by the names a script uses (`tell application "Terminal"`, `Application('Keychain Access')`).
let hardDenyNames: [String] = ["keychain access", "passwords", "system settings", "system preferences", "securityagent",
  "terminal", "iterm", "iterm2", "1password", "1password 7", "bitwarden", "screen sharing", "console"]
let browsers: Set<String> = ["com.google.Chrome", "com.google.Chrome.canary", "com.apple.Safari",
  "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser"]

func readList(_ path: String) -> [String] {
  guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { missing.append(path); return [] }
  return s.split(separator: "\n").map { l in
    String(l.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
      .split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
  }.filter { !$0.isEmpty }
}
func loadPolicy(_ cfg: [String: String]) {
  allowed = []; missing = []
  for p in (cfg["bundles"] ?? "").split(separator: ":") { allowed.formUnion(readList(String(p))) }
  words = (cfg["words"].map { readList($0) } ?? []).map { $0.lowercased() }
  hosts = []
  for p in (cfg["hosts"] ?? "").split(separator: ":") { hosts += readList(String(p)).map { $0.lowercased() } }
}

// ── apps and focus evidence ──
func app(_ bundle: String) throws -> NSRunningApplication {
  if hardDeny.contains(bundle) { throw Fail(msg: "[desktop:hard-deny] refused: \(bundle) is on the hard deny list (secrets or system controls)") }
  if !allowed.contains(bundle) { throw Fail(msg: "[desktop:app-allow] refused: \(bundle) is not on the allow-list (contracts/desktop-agent-bundles.txt or the private layer)") }
  guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
    throw Fail(msg: "not running: \(bundle)") }
  return a
}
func gen(_ a: NSRunningApplication) -> String {
  "\(a.processIdentifier):\(Int(a.launchDate?.timeIntervalSince1970 ?? 0))"
}
func front() -> String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?" }
func pointer() -> String { let p = NSEvent.mouseLocation; return "\(Int(p.x)),\(Int(p.y))" }
func evidence(_ before: (String, String)) -> [String: Any] {
  usleep(150_000)
  let after = (front(), pointer())
  return ["front_before": before.0, "front_after": after.0, "pointer_before": before.1, "pointer_after": after.1,
          "took_focus": before.0 != after.0, "moved_pointer": before.1 != after.1]
}

// ── Accessibility ──
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ n: String) -> String? {
  guard let v = attr(e, n) else { return nil }
  if let s = v as? String { return s.isEmpty ? nil : s }
  if let num = v as? NSNumber { return num.stringValue }
  if CFGetTypeID(v) == CFURLGetTypeID() { return (v as! URL).absoluteString }
  return nil
}
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func actions(_ e: AXUIElement) -> [String] {
  var a: CFArray?
  return AXUIElementCopyActionNames(e, &a) == .success ? ((a as? [String]) ?? []) : []
}
// cut nil is for the gates: a live word past the display cut still asks (review F7).
func labelOf(_ parts: [String], cut: Int?) -> String {
  parts.map { p in cut.map { String(p.prefix($0)) } ?? p }.joined(separator: " | ")
}
func label(_ e: AXUIElement, cut: Int? = 120) -> String {
  labelOf([kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, "AXIdentifier", kAXHelpAttribute]
    .compactMap { str(e, $0) }, cut: cut)
}
func root(_ a: NSRunningApplication) -> AXUIElement {
  let r = AXUIElementCreateApplication(a.processIdentifier)
  AXUIElementSetMessagingTimeout(r, 3.0)
  return r
}
func resolve(_ a: NSRunningApplication, _ ref: String) throws -> AXUIElement {
  var e = root(a)
  for part in ref.split(separator: ".") {
    guard let i = Int(part) else { throw Fail(msg: "bad ref \(ref)") }
    let k = kids(e)
    guard i >= 0 && i < k.count else { throw Fail(msg: "stale ref \(ref): the tree changed; read it again") }
    e = k[i]
  }
  return e
}
// Refs are positions, and an app can re-lay its tree between reads (Calculator swaps AC for C): the caller names the
// label it read, so a moved ref is refused instead of acting on a neighbour.
func expectLabel(_ e: AXUIElement, _ r: [String: Any]) throws -> String { try expectMatch(label(e), r); return label(e, cut: nil) }
func expectMatch(_ lab: String, _ r: [String: Any]) throws {
  guard let want = r["expect"] as? String, !want.isEmpty else {
    throw Fail(msg: "[desktop:expect-label] expect missing: pass the element's label from tree, so a moved ref is refused") }
  if !lab.contains(want) { throw Fail(msg: "[desktop:expect-label] stale ref: element reads '\(lab)', expected '\(want)'") }
}
func checkGen(_ a: NSRunningApplication, _ r: [String: Any]) throws {
  if let g = r["gen"] as? String, g != gen(a) {
    throw Fail(msg: "stale: \(a.bundleIdentifier ?? "") restarted since the tree was read (gen \(g) → \(gen(a)))") }
}
func isBrowser(_ a: NSRunningApplication) -> Bool { browsers.contains(a.bundleIdentifier ?? "") }
func hostAllowed(_ h: String) -> Bool { hosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) }
// A browser is admitted only while the page in the window acted on (default: the focused one, where keys and text
// land) is on the browser host allow-list (harbor chrome's list). A ref names its own window (review F4).
func browserGate(_ a: NSRunningApplication, window: AXUIElement? = nil, wait: Bool = true) throws {
  guard isBrowser(a) else { return }
  var url: String? = nil
  func walk(_ e: AXUIElement, _ d: Int) {
    if url != nil || d > 30 { return }
    if (str(e, kAXRoleAttribute) ?? "") == "AXWebArea", let u = str(e, "AXURL") { url = u; return }
    for k in kids(e) { walk(k, d + 1) }
  }
  let ra = root(a)
  func look() { if let w = window ?? attr(ra, kAXFocusedWindowAttribute).map({ $0 as! AXUIElement }) { walk(w, 0) } }
  look()
  if url == nil && wait {  // Chromium builds its web tree only when an assistive client asks; ask, then look again
    AXUIElementSetAttributeValue(ra, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(ra, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    for _ in 0..<8 where url == nil { usleep(250_000); look() }  // the tree builds asynchronously: up to 2 s
  }
  guard let u = url, let h = URL(string: u)?.host?.lowercased() else {
    throw Fail(msg: "[desktop:browser-host] refused: cannot read the browser's page address, so the host allow-list cannot be checked") }
  if !hostAllowed(h) {
    throw Fail(msg: "[desktop:browser-host] refused: \(h) is not on the browser host allow-list (contracts/browser-agent-hosts.txt)") }
}
// The window a ref sits in: its first step from the app root, when that is a window.
func refWindow(_ a: NSRunningApplication, _ ref: String) -> AXUIElement? {
  guard let i = ref.split(separator: ".").first.flatMap({ Int($0) }) else { return nil }
  let k = kids(root(a))
  return i >= 0 && i < k.count && str(k[i], kAXRoleAttribute) == "AXWindow" ? k[i] : nil
}
func liveWord(_ s: String) -> String? {
  let l = s.lowercased()
  return words.first { w in
    l.range(of: "(^|[^\\p{L}])" + NSRegularExpression.escapedPattern(for: w) + "($|[^\\p{L}])",
            options: .regularExpression) != nil }
}
func gate(_ text: String, _ r: [String: Any]) throws {
  if words.isEmpty && (r["confirmed"] as? Bool) != true {  // a missing list refuses, never waves through
    throw Fail(msg: "[desktop:live-change-list] live change refused: contracts/live-change-words.txt is missing or empty") }
  if let w = liveWord(text), (r["confirmed"] as? Bool) != true {
    throw Fail(msg: "[desktop:live-change-word] live change refused: '\(text.prefix(80))' matches '\(w)' — the operator confirms one call") }
}

func tree(_ a: NSRunningApplication, _ r: [String: Any]) -> [String: Any] {
  let maxDepth = (r["depth"] as? Int) ?? 14, cap = (r["max"] as? Int) ?? 1500
  var lines: [String] = [], n = 0, deeper = false
  let ra = root(a), browser = isBrowser(a)
  if browser {  // build every window's web tree once, so each window is checked without its own 2 s wait
    AXUIElementSetAttributeValue(ra, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(ra, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    usleep(1_000_000)
  }
  if (r["enhance"] as? Bool) == true {  // Chromium/Electron build their tree only when asked
    AXUIElementSetAttributeValue(ra, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(ra, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    usleep(300_000)
  }
  func walk(_ e: AXUIElement, _ ref: String, _ d: Int) {
    if n >= cap || d > maxDepth { deeper = deeper || d > maxDepth; return }
    n += 1
    let role = str(e, kAXRoleAttribute) ?? "?"
    if browser && d == 1 && role == "AXWindow" {  // each browser window is read only while its page is allowed
      if (try? browserGate(a, window: e, wait: false)) == nil {  // the refused page's host is not named either
        lines.append(" \(ref) AXWindow (not read: its page is off the browser host list or unreadable)"); return }
    }
    let acts = actions(e).filter { $0.hasPrefix("AX") && !["AXScrollToVisible", "AXShowDefaultUI", "AXShowAlternateUI"].contains($0) }
    let lab = label(e)
    if !(lab.isEmpty && acts.isEmpty && ["AXGroup", "AXUnknown", "AXSplitGroup", "AXLayoutArea"].contains(role)) {
      lines.append("\(String(repeating: " ", count: min(d, 12)))\(ref.isEmpty ? "app" : ref) \(role)"
        + (lab.isEmpty ? "" : " \"\(lab)\"") + (acts.isEmpty ? "" : " [\(acts.joined(separator: ","))]"))
    }
    for (i, k) in kids(e).enumerated() { walk(k, ref.isEmpty ? "\(i)" : "\(ref).\(i)", d + 1) }
  }
  walk(ra, "", 0)
  return ["gen": gen(a), "nodes": n, "truncated": n >= cap || deeper, "tree": lines.joined(separator: "\n")]
}

let backgroundActions: Set<String> = ["AXPress", "AXShowMenu", "AXIncrement", "AXDecrement", "AXConfirm",
                                      "AXCancel", "AXPick", "AXOpen"]
func focusGate(_ name: String, _ r: [String: Any]) throws {
  if !backgroundActions.contains(name) && (r["foreground"] as? Bool) != true {
    throw Fail(msg: "[desktop:focus] refused: \(name) may take focus; pass foreground to allow it") }
}
func act(_ a: NSRunningApplication, _ r: [String: Any]) throws -> [String: Any] {
  try checkGen(a, r); try browserGate(a, window: refWindow(a, (r["ref"] as? String) ?? ""))
  let name = (r["action"] as? String) ?? "AXPress"
  try focusGate(name, r)
  let e = try resolve(a, (r["ref"] as? String) ?? "")
  let lab = try expectLabel(e, r)
  try gate(lab, r)
  let b = (front(), pointer())
  let err = AXUIElementPerformAction(e, name as CFString)
  if err != .success { throw Fail(msg: "\(name) failed: AXError \(err.rawValue)") }
  return ["done": name, "label": String(lab.prefix(240))].merging(evidence(b)) { x, _ in x }
}
func setValue(_ a: NSRunningApplication, _ r: [String: Any]) throws -> [String: Any] {
  try checkGen(a, r); try browserGate(a, window: refWindow(a, (r["ref"] as? String) ?? ""))
  let e = try resolve(a, (r["ref"] as? String) ?? "")
  let lab = try expectLabel(e, r)
  try gate(lab, r)  // a checkbox or switch set by value is a press by another name
  guard let v = r["value"] as? String else { throw Fail(msg: "value missing") }
  let b = (front(), pointer())
  let err = AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, v as CFString)
  if err != .success { throw Fail(msg: "set value failed: AXError \(err.rawValue) (field may not be settable; try type)") }
  return ["done": "set", "label": label(e), "readback": str(e, kAXValueAttribute) ?? ""].merging(evidence(b)) { x, _ in x }
}
func menu(_ a: NSRunningApplication, _ r: [String: Any]) throws -> [String: Any] {
  try browserGate(a)
  let path = ((r["path"] as? String) ?? "").components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
  guard path.count >= 2, let bar = attr(root(a), kAXMenuBarAttribute) else { throw Fail(msg: "menu path needs 'Menu > Item'") }
  var e = bar as! AXUIElement
  for (i, want) in path.enumerated() {
    let pool = i == 0 ? kids(e) : kids(e).flatMap { str($0, kAXRoleAttribute) == "AXMenu" ? kids($0) : [$0] }
    guard let hit = pool.first(where: { (str($0, kAXTitleAttribute) ?? "").lowercased() == want.lowercased() }) else {
      throw Fail(msg: "menu item not found: \(want); have: \(pool.compactMap { str($0, kAXTitleAttribute) }.joined(separator: ", "))") }
    e = hit
  }
  try gate(path.joined(separator: " > "), r)
  if (str(e, kAXEnabledAttribute) ?? "1") == "0" { throw Fail(msg: "menu item disabled: \(path.last!)") }
  let b = (front(), pointer())
  let err = AXUIElementPerformAction(e, kAXPressAction as CFString)
  if err != .success { throw Fail(msg: "menu press failed: AXError \(err.rawValue)") }
  return ["done": "menu", "path": path.joined(separator: " > ")].merging(evidence(b)) { x, _ in x }
}

// ── keyboard, posted to one process (never the session's event stream) ──
let named: [String: CGKeyCode] = ["return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51, "escape": 53,
  "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
  "forwarddelete": 117]
// Return, keypad Enter and Space submit or press the focused control (D-94's set); a typed line break is a Return.
let submitKeys: Set<String> = ["return", "enter", "space"]
func submitGate(_ k: String, _ r: [String: Any]) throws {
  if submitKeys.contains(k) && (r["confirmed"] as? Bool) != true {
    throw Fail(msg: "[desktop:submit-key] live change refused: \(k) can submit a form or press a button — the operator confirms one call") }
}
func typeGate(_ text: String) throws {
  if text.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" || $0 == "\u{3}" }) {
    throw Fail(msg: "[desktop:type-newline] live change refused: a typed line break submits like Enter — type the text without it, then confirm_key return") }
}
func typeText(_ a: NSRunningApplication, _ r: [String: Any]) throws -> [String: Any] {
  try browserGate(a)
  guard let text = r["text"] as? String else { throw Fail(msg: "text missing") }
  try typeGate(text)
  let b = (front(), pointer())
  for (i, var u) in text.utf16.enumerated() {
    for down in [true, false] {
      guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else {
        throw Fail(msg: "type stopped: no key event for UTF-16 unit \(i) of \(text.utf16.count); the text is partly typed") }
      ev.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
      ev.postToPid(a.processIdentifier)
    }
    usleep(6_000)
  }
  return ["done": "type", "chars": text.count].merging(evidence(b)) { x, _ in x }
}
func key(_ a: NSRunningApplication, _ r: [String: Any]) throws -> [String: Any] {
  try browserGate(a)
  let parts = ((r["combo"] as? String) ?? "").lowercased().split(separator: "+").map(String.init)
  guard let k = parts.last, let code = named[k] else {
    throw Fail(msg: "key: named keys only (\(named.keys.sorted().joined(separator: ","))); letter shortcuts go through menu") }
  try submitGate(k, r)
  var flags: CGEventFlags = []
  for m in parts.dropLast() {
    switch m { case "cmd": flags.insert(.maskCommand); case "shift": flags.insert(.maskShift)
      case "alt", "opt": flags.insert(.maskAlternate); case "ctrl": flags.insert(.maskControl)
      default: throw Fail(msg: "unknown modifier \(m)") }
  }
  let b = (front(), pointer())
  for down in [true, false] {
    let ev = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    ev.flags = flags
    ev.postToPid(a.processIdentifier)
  }
  return ["done": "key", "combo": parts.joined(separator: "+")].merging(evidence(b)) { x, _ in x }
}

// ── screenshots of one window, without raising it ──
func pruneShots(_ dir: String) {  // a day of shots is kept; older ones go (review F9)
  let fm = FileManager.default, old = Date().addingTimeInterval(-86_400)
  for f in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where f.hasPrefix("shot-") && f.hasSuffix(".png") {
    let p = dir + "/" + f
    if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, m < old { try? fm.removeItem(atPath: p) }
  }
}
func shot(_ a: NSRunningApplication, _ r: [String: Any], _ dir: String) throws -> [String: Any] {
  let sem = DispatchSemaphore(value: 0)
  var out: Result<[String: Any], Error> = .failure(Fail(msg: "no result"))
  let pid = a.processIdentifier
  Task {
    do {
      let c = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
      let ws = c.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 80 }
      let want = (r["title"] as? String)?.lowercased()
      let pick = want.flatMap { t in ws.first { ($0.title ?? "").lowercased().contains(t) } }
        ?? ws.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
      guard let w = pick else { throw Fail(msg: "no window to capture") }
      if isBrowser(a) {  // the captured window's own page must pass the host gate (review F4)
        let same = kids(root(a)).filter { str($0, kAXRoleAttribute) == "AXWindow" && (str($0, kAXTitleAttribute) ?? "") == (w.title ?? "") }
        guard same.count == 1, ws.filter({ ($0.title ?? "") == (w.title ?? "") }).count == 1 else {
          throw Fail(msg: "[desktop:browser-host] refused: the browser window's title is not unique, so its page host cannot be checked") }
        try browserGate(a, window: same[0])
      }
      pruneShots(dir)
      let f = SCContentFilter(desktopIndependentWindow: w)
      let cfg = SCStreamConfiguration()
      cfg.width = Int(w.frame.width * CGFloat(f.pointPixelScale))
      cfg.height = Int(w.frame.height * CGFloat(f.pointPixelScale))
      cfg.showsCursor = false
      let img = try await SCScreenshotManager.captureImage(contentFilter: f, configuration: cfg)
      let path = dir + "/shot-\(Int(Date().timeIntervalSince1970 * 1000)).png"
      guard let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                    UTType.png.identifier as CFString, 1, nil) else { throw Fail(msg: "cannot write \(path)") }
      CGImageDestinationAddImage(d, img, nil)
      guard CGImageDestinationFinalize(d) else { throw Fail(msg: "png write failed") }
      out = .success(["path": path, "window": w.title ?? "", "width": img.width, "height": img.height,
                      "on_screen": w.isOnScreen])
    } catch { out = .failure(error) }
    sem.signal()
  }
  if sem.wait(timeout: .now() + 20) == .timedOut { throw Fail(msg: "capture timed out") }
  return try out.get()
}

// ── Apple Events (AppleScript / JXA), run in this process so Automation consent is this app's ──
// A script that names a hard-denied app is refused before the dialog. Best effort: a script can still reach one
// indirectly (do shell script, a variable app name), so for scripts the operator's dialog stays the boundary.
func scriptDeny(_ src: String) throws {
  let l = src.lowercased()
  for id in hardDeny where l.contains(id.lowercased()) { throw Fail(msg: "[desktop:script-deny] refused: the script names \(id), on the hard deny list") }
  for n in hardDenyNames where l.contains("\"\(n)\"") || l.contains("'\(n)'")
    || l.contains("\"\(n).app") || l.contains("'\(n).app") || l.contains("/\(n).app") {
    throw Fail(msg: "[desktop:script-deny] refused: the script names \(n), on the hard deny list") }
}
// The confirm gates are apart from the runs, so the self-test (and a mutant) never runs a script or a Shortcut.
func scriptGate(_ r: [String: Any]) throws {
  try scriptDeny((r["source"] as? String) ?? "")
  guard (r["confirmed"] as? Bool) == true else { throw Fail(msg: "[desktop:script-confirm] script refused: every script is a change the operator confirms") }
}
func shortcutGate(_ r: [String: Any]) throws {
  if (r["name"] as? String) != nil && (r["confirmed"] as? Bool) != true { throw Fail(msg: "[desktop:shortcut-confirm] shortcut refused: a run is a change the operator confirms") }
}
func script(_ r: [String: Any]) throws -> [String: Any] {
  try scriptGate(r)
  guard let src = r["source"] as? String else { throw Fail(msg: "source missing") }
  let lang = (r["language"] as? String) == "javascript" ? "JavaScript" : "AppleScript"
  var res: [String: Any] = [:], failure: String? = nil
  DispatchQueue.main.sync {
    let s = OSAScript(source: src, language: OSALanguage(forName: lang))
    var info: NSDictionary?
    if let d = s.executeAndReturnError(&info) { res = ["result": d.stringValue ?? ""] }
    else {
      let num = (info?[OSAScriptErrorNumberKey] as? Int) ?? 0
      let hint = num == -1743 ? " (Automation not granted: System Settings → Privacy & Security → Automation → HarborDesktop)"
        : num == -600 ? " (target app not running)" : ""
      failure = "script error \(num): \((info?[OSAScriptErrorMessageKey] as? String) ?? "?")\(hint)"
    }
  }
  if let f = failure { throw Fail(msg: f) }
  return res
}
func shortcuts(_ r: [String: Any]) throws -> [String: Any] {
  try shortcutGate(r)
  let run = (r["name"] as? String) != nil
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
  p.arguments = run ? ["run", r["name"] as! String] + ((r["input"] as? String).map { ["-i", $0] } ?? []) : ["list"]
  let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
  try p.run()
  // Drain both pipes while it runs: waiting first deadlocks once output fills the pipe (~64 KB). Under nc's 30 s.
  var od = Data(), ed = Data()
  let g = DispatchGroup()
  g.enter(); DispatchQueue.global().async { od = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
  g.enter(); DispatchQueue.global().async { ed = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
  if g.wait(timeout: .now() + 25) == .timedOut { p.terminate(); throw Fail(msg: "shortcut stopped: no result in 25 s") }
  p.waitUntilExit()
  let out = String(data: od, encoding: .utf8) ?? ""
  if p.terminationStatus != 0 { throw Fail(msg: "shortcuts exit \(p.terminationStatus): \(String(data: ed, encoding: .utf8) ?? "")") }
  return ["result": String(out.prefix(20000)), "truncated": out.count > 20000]
}

// ── dispatch ──
var state = ""
func oneLine(_ s: String, _ n: Int) -> String {
  String(s.prefix(n)).replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
}
// What a row is about: the app, or for a script its source and for a Shortcut its name (review F8).
func subject(_ verb: String, _ r: [String: Any]) -> String {
  if verb == "script" { return "script:" + oneLine((r["source"] as? String) ?? "", 120) }
  if verb == "shortcuts" { return (r["name"] as? String).map { "shortcut:" + oneLine($0, 80) } ?? "shortcuts:list" }
  return (r["bundle"] as? String).map { oneLine($0, 120) } ?? "-"
}
// Appends with O_APPEND (never truncates); returns false when the row could not be written (review F21).
func audit(_ verb: String, _ r: [String: Any], _ ok: Bool, _ msg: String) -> Bool {
  let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(verb)\t\(subject(verb, r))\t\(ok ? "ok" : "refused")\t\(oneLine(msg, 160))\n"
  let fd = open(state + "/audit.tsv", O_WRONLY | O_APPEND | O_CREAT, 0o600)
  if fd < 0 { return false }
  defer { close(fd) }
  let d = Data(line.utf8)
  return d.withUnsafeBytes { write(fd, $0.baseAddress, d.count) } == d.count
}
func handle(_ r: [String: Any]) -> [String: Any] {
  let verb = (r["verb"] as? String) ?? ""
  do {
    var res: [String: Any]
    switch verb {
    case "doctor":
      res = ["version": version, "pid": getpid(), "path": Bundle.main.bundlePath,
             "accessibility": AXIsProcessTrusted(), "screen_recording": CGPreflightScreenCaptureAccess(),
             "allowed": allowed.sorted(), "missing": missing, "words": words.count, "hosts": hosts.count, "front": front()]
    case "request-access":
      let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      res = ["accessibility": AXIsProcessTrustedWithOptions(opts), "screen_recording": CGRequestScreenCaptureAccess()]
    case "apps":
      res = ["apps": NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map {
        let b = $0.bundleIdentifier ?? "?"
        return "\(b)\t\($0.localizedName ?? "")\t\(hardDeny.contains(b) ? "denied" : allowed.contains(b) ? "allowed" : "not-allowed")\t\($0.isActive ? "front" : "")"
      }.joined(separator: "\n")]
    case "windows":
      let a = try app((r["bundle"] as? String) ?? "")
      res = ["gen": gen(a), "windows": kids(root(a)).enumerated().compactMap { i, w in
        str(w, kAXRoleAttribute) == "AXWindow" ? "\(i) \"\(str(w, kAXTitleAttribute) ?? "")\"\(str(w, kAXMinimizedAttribute) == "1" ? " minimized" : "")" : nil
      }.joined(separator: "\n")]
    case "tree": res = tree(try app((r["bundle"] as? String) ?? ""), r)
    case "action": res = try act(try app((r["bundle"] as? String) ?? ""), r)
    case "set-value": res = try setValue(try app((r["bundle"] as? String) ?? ""), r)
    case "menu": res = try menu(try app((r["bundle"] as? String) ?? ""), r)
    case "type": res = try typeText(try app((r["bundle"] as? String) ?? ""), r)
    case "key": res = try key(try app((r["bundle"] as? String) ?? ""), r)
    case "shot": res = try shot(try app((r["bundle"] as? String) ?? ""), r, state)
    case "script": res = try script(r)
    case "shortcuts": res = try shortcuts(r)
    default: throw Fail(msg: "unknown verb '\(verb)'")
    }
    if !["doctor", "apps", "windows", "tree", "shot"].contains(verb) || r["confirmed"] as? Bool == true {
      if !audit(verb, r, true, (res["label"] as? String) ?? (res["path"] as? String) ?? "") { res["audit"] = "write failed: \(state)/audit.tsv" } }
    res["ok"] = true
    return res
  } catch {
    let m = (error as? Fail)?.msg ?? "\(error)"
    if !["doctor", "apps"].contains(verb) && !audit(verb, r, false, m) { return ["ok": false, "error": m, "audit": "write failed: \(state)/audit.tsv"] }
    return ["ok": false, "error": m]
  }
}

// ── socket server: owner-only, exits when idle ──
func serve(_ sock: String, _ cfg: [String: String]) -> Never {
  loadPolicy(cfg)
  state = (sock as NSString).deletingLastPathComponent
  unlink(sock)
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
  let path = Array(sock.utf8)
  guard path.count < MemoryLayout.size(ofValue: addr.sun_path) else { FileHandle.standardError.write("socket path too long\n".data(using: .utf8)!); exit(2) }
  withUnsafeMutableBytes(of: &addr.sun_path) { p in for (i, c) in path.enumerated() { p[i] = c } }
  let len = socklen_t(MemoryLayout<sockaddr_un>.size)
  guard withUnsafePointer(to: &addr, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }) == 0,
        listen(fd, 8) == 0 else { FileHandle.standardError.write("bind failed \(errno)\n".data(using: .utf8)!); exit(2) }
  chmod(sock, 0o600)
  var last = Date()
  let idle = Double(cfg["idle"] ?? "900") ?? 900
  Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in if Date().timeIntervalSince(last) > idle { unlink(sock); exit(0) } }
  DispatchQueue.global().async {
    while true {
      let c = accept(fd, nil, nil); if c < 0 { continue }
      var uid: uid_t = 0, gid: gid_t = 0
      if getpeereid(c, &uid, &gid) != 0 || uid != getuid() { close(c); continue }
      last = Date()
      var buf = Data(); var b = [UInt8](repeating: 0, count: 65536)
      while !buf.contains(10) { let n = read(c, &b, b.count); if n <= 0 { break }; buf.append(contentsOf: b[0..<n]) }
      var reply: [String: Any]
      if let line = buf.split(separator: 10).first, let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
        if (r["verb"] as? String) == "reload" { loadPolicy(cfg); reply = ["ok": true, "allowed": allowed.count] }
        else { reply = handle(r) }
      } else { reply = ["ok": false, "error": "bad request: one JSON object per line"] }
      var out = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{\"ok\":false}".utf8); out.append(10)
      out.withUnsafeBytes { _ = write(c, $0.baseAddress, out.count) }
      close(c)
    }
  }
  NSApplication.shared.setActivationPolicy(.prohibited)
  NSApplication.shared.run()
  exit(0)
}

// selftest: the policy with no grants and no apps — what the suite asserts, and what a mutant must turn red.
func selftest(_ cfg: [String: String]) -> Never {
  loadPolicy(cfg)
  var bad = 0
  func check(_ name: String, _ ok: Bool) { print("\(ok ? "ok" : "FAIL") \(name)"); if !ok { bad += 1 } }
  func refused(_ f: () throws -> Void) -> String { do { try f(); return "" } catch { return (error as? Fail)?.msg ?? "\(error)" } }
  check("words loaded", words.count >= 10)
  check("a live-change label is caught (Save)", liveWord("Save") == "save")
  check("a phrase inside a label is caught (Delete draft)", liveWord("Delete draft | button") != nil)
  check("status text passes (Saved)", liveWord("Saved") == nil)
  check("a listed word inside a longer word passes (Sender)", liveWord("Sender") == nil)
  check("gate refuses a live label unconfirmed", refused { try gate("Send", [:]) }.contains("[desktop:live-change-word]"))
  check("gate passes it confirmed", refused { try gate("Send", ["confirmed": true]) } == "")
  check("gate passes a plain label", refused { try gate("Seven", [:]) } == "")
  allowed.insert("com.apple.keychainaccess")
  check("the hard deny wins over the allow-list", refused { _ = try app("com.apple.keychainaccess") }.contains("[desktop:hard-deny]"))
  check("an unlisted app is refused", refused { _ = try app("com.example.unlisted") }.contains("[desktop:app-allow]"))
  check("a ref with no expected label is refused", refused { try expectMatch("7 | Seven", [:]) }.contains("[desktop:expect-label] expect missing"))
  check("a moved ref is refused (reads 8, expected 7)", refused { try expectMatch("8 | Eight", ["expect": "Seven"]) }.contains("[desktop:expect-label] stale ref"))
  check("the ref still on its label passes", refused { try expectMatch("7 | Seven", ["expect": "Seven"]) } == "")
  check("Space needs a confirm (it presses the focused button)", refused { try submitGate("space", [:]) }.contains("[desktop:submit-key]"))
  check("Return needs a confirm", refused { try submitGate("return", [:]) }.contains("[desktop:submit-key]"))
  check("a confirmed Return passes", refused { try submitGate("return", ["confirmed": true]) } == "")
  check("Tab passes", refused { try submitGate("tab", [:]) } == "")
  check("a typed line break is refused", refused { try typeGate("hello\nworld") }.contains("[desktop:type-newline]"))
  check("plain typed text passes", refused { try typeGate("labas, pasauli") } == "")
  check("a script naming Terminal is refused", refused { try scriptDeny("tell application \"Terminal\" to do script \"ls\"") }.contains("[desktop:script-deny]"))
  check("a JXA script naming Keychain Access is refused", refused { try scriptDeny("Application('Keychain Access').activate()") }.contains("[desktop:script-deny]"))
  check("a script naming a denied bundle id is refused", refused { try scriptDeny("tell application id \"com.apple.Terminal\" to quit") }.contains("[desktop:script-deny]"))
  check("a script for TextEdit passes", refused { try scriptDeny("tell application \"TextEdit\" to get name of front document") } == "")
  check("a live word past the display cut still asks", refused { try gate(labelOf([String(repeating: "x", count: 200) + " Delete"], cut: nil), [:]) }.contains("live change refused"))
  hosts = ["example.com"]
  check("a listed host and its subdomain pass", hostAllowed("example.com") && hostAllowed("a.example.com"))
  check("a lookalike host is refused", !hostAllowed("badexample.com"))
  check("a script row names its source, whatever bundle it carries", subject("script", ["source": "beep\n2", "bundle": "x"]) == "script:beep 2")
  check("a Shortcut row names it", subject("shortcuts", ["name": "Make GIF"]) == "shortcut:Make GIF")
  check("a bundle cannot forge a row", !subject("key", ["bundle": "a\tb\nc"]).contains(where: { $0 == "\t" || $0 == "\n" }))
  check("a script naming Terminal.app by path is refused", refused { try scriptDeny("tell application \"/System/Applications/Utilities/Terminal.app\" to quit") }.contains("[desktop:script-deny]"))
  check("an AXPress needs no foreground", refused { try focusGate("AXPress", [:]) } == "")
  check("an action that may take focus is refused", refused { try focusGate("AXRaise", [:]) }.contains("[desktop:focus]"))
  check("a script unconfirmed is refused before it runs", refused { try scriptGate(["source": "beep"]) }.contains("[desktop:script-confirm]"))
  check("a confirmed script passes its gate", refused { try scriptGate(["source": "beep", "confirmed": true]) } == "")
  check("listing Shortcuts needs no confirm", refused { try shortcutGate([:]) } == "")
  check("a Shortcut run unconfirmed is refused before it runs", refused { try shortcutGate(["name": "x"]) }.contains("[desktop:shortcut-confirm]"))
  let keep = words; words = []
  check("an empty word list refuses every guarded call", refused { try gate("Seven", [:]) }.contains("[desktop:live-change-list]"))
  words = keep
  print(bad == 0 ? "selftest: all passed" : "selftest: \(bad) failed")
  exit(bad == 0 ? 0 : 1)
}

// argv: serve <socket> key=value… (bundles=a:b words=f hosts=a:b idle=s) | selftest words=f
let argv = CommandLine.arguments
if argv.count >= 2 && argv[1] == "selftest" {
  var cfg: [String: String] = [:]
  for kv in argv.dropFirst(2) { let p = kv.split(separator: "=", maxSplits: 1); if p.count == 2 { cfg[String(p[0])] = String(p[1]) } }
  selftest(cfg)
}
if argv.count >= 3 && argv[1] == "serve" {
  var cfg: [String: String] = [:]
  for kv in argv.dropFirst(3) { let p = kv.split(separator: "=", maxSplits: 1); if p.count == 2 { cfg[String(p[0])] = String(p[1]) } }
  serve(argv[2], cfg)
}
print("usage: HarborDesktop serve <socket> bundles=<file:file> words=<file> hosts=<file:file> idle=<seconds>")
exit(64)
