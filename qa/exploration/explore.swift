// qa/exploration/explore.swift
// Standalone macOS Accessibility (AX) exploration harness for Rawenv.app.
// Launches the GUI binary with --ui-testing (seeded data), then drives every
// reachable control, capturing a BEFORE and AFTER screenshot around each action,
// naming files <NNN>_<screen>_<action>_<before|after>.png and writing a
// manifest.json that catalogs each screenshot's context.
//
// Run (inside the Tart VM, which has Accessibility permission for SSH sessions):
//   swift explore.swift <gui-binary-path> <output-dir>
// e.g. swift explore.swift /tmp/vmbuild/debug/Rawenv /tmp/rawenv-exploration
//
// AX primitives mirror gui/macos/Tests/RawenvE2ETests/ComprehensiveUIE2ETests.swift.

import AppKit
import Foundation

let argv = CommandLine.arguments
let binaryPath = argv.count > 1 ? argv[1] : "/tmp/vmbuild/debug/Rawenv"
let outDir = argv.count > 2 ? argv[2] : "\(NSHomeDirectory())/rawenv-exploration"
let settle = 0.6

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - AX primitives
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(e, a as CFString, &v)
    return v
}
func axStr(_ e: AXUIElement, _ a: String) -> String? { attr(e, a) as? String }
func axChildren(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func axWindows(_ app: AXUIElement) -> [AXUIElement] { (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }
func findById(_ root: AXUIElement, _ id: String, _ depth: Int = 0) -> AXUIElement? {
    if axStr(root, kAXIdentifierAttribute) == id { return root }
    guard depth < 22 else { return nil }
    for c in axChildren(root) { if let f = findById(c, id, depth + 1) { return f } }
    return nil
}
func findAll(_ root: AXUIElement, _ depth: Int = 0, _ pred: (AXUIElement) -> Bool) -> [AXUIElement] {
    var r: [AXUIElement] = []
    if pred(root) { r.append(root) }
    guard depth < 22 else { return r }
    for c in axChildren(root) { r += findAll(c, depth + 1, pred) }
    return r
}
func findAllByPrefix(_ root: AXUIElement, _ prefix: String) -> [AXUIElement] {
    findAll(root) { (axStr($0, kAXIdentifierAttribute) ?? "").hasPrefix(prefix) }
}
func axParentRow(_ root: AXUIElement, _ id: String, _ depth: Int = 0) -> AXUIElement? {
    if axStr(root, kAXRoleAttribute) == "AXRow", findById(root, id) != nil { return root }
    guard depth < 22 else { return nil }
    for c in axChildren(root) { if let f = axParentRow(c, id, depth + 1) { return f } }
    return nil
}
func press(_ e: AXUIElement) { AXUIElementPerformAction(e, kAXPressAction as CFString) }
func setVal(_ e: AXUIElement, _ v: String) {
    AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, v as CFString)
}

// MARK: - Launch
guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
    FileHandle.standardError.write("binary not found/executable: \(binaryPath)\n".data(using: .utf8)!)
    exit(2)
}
let proc = Process()
proc.executableURL = URL(fileURLWithPath: binaryPath)
proc.arguments = ["--ui-testing"]
try proc.run()
Thread.sleep(forTimeInterval: 3.5)
let app = AXUIElementCreateApplication(proc.processIdentifier)
NSRunningApplication(processIdentifier: proc.processIdentifier)?.activate(options: [])
Thread.sleep(forTimeInterval: 0.8)

func currentWindow() -> AXUIElement? { axWindows(app).first }

// MARK: - Screenshot + manifest
struct Entry: Codable {
    let step: Int
    let screen: String
    let action: String
    let description: String
    let before: String
    let after: String
}
var manifest: [Entry] = []
var stepNum = 0

func capture(_ file: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "\(outDir)/\(file)"]
    try? p.run()
    p.waitUntilExit()
}

/// One cataloged interaction: shot before -> run action -> settle -> shot after -> record.
func step(_ screen: String, _ action: String, _ desc: String, _ act: () -> Void) {
    stepNum += 1
    let n = String(format: "%03d", stepNum)
    let slug = action.replacingOccurrences(of: " ", with: "-")
    let before = "\(n)_\(screen)_\(slug)_before.png"
    let after = "\(n)_\(screen)_\(slug)_after.png"
    capture(before)
    act()
    Thread.sleep(forTimeInterval: settle)
    capture(after)
    manifest.append(
        Entry(step: stepNum, screen: screen, action: action, description: desc, before: before, after: after))
    FileHandle.standardOutput.write("step \(n): \(screen) / \(action)\n".data(using: .utf8)!)
}

func selectNav(_ id: String) {
    guard let w = currentWindow(), let list = findById(w, "sidebar"), let row = axParentRow(w, id) else { return }
    AXUIElementSetAttributeValue(list, "AXSelectedRows" as CFString, [row] as CFArray)
}
func tap(_ id: String) {
    if let w = currentWindow(), let e = findById(w, id) { press(e) }
}
func typeIn(_ id: String, _ v: String) {
    if let w = currentWindow(), let e = findById(w, id) { setVal(e, v) }
}

// MARK: - Exploration plan

let navItems: [(String, String)] = [
    ("nav_dashboard", "dashboard"), ("nav_discovery", "discovery"), ("nav_ai_chat", "ai-chat"),
    ("nav_connections", "connections"), ("nav_deploy", "deploy"), ("nav_tunnel", "tunnel"),
    ("nav_uninstall", "uninstall"), ("nav_settings", "settings"),
]

// Pass 1 — sidebar navigation (every top-level screen)
for (id, screen) in navItems {
    step(screen, "open", "Navigate to the \(screen) screen via the sidebar", { selectNav(id) })
}

// Pass 2 — Dashboard detail tabs + service controls
selectNav("nav_dashboard")
Thread.sleep(forTimeInterval: settle)
for tab in ["tab_logs", "tab_config", "tab_connection", "tab_cell", "tab_backups"] {
    step(
        "dashboard", "tab-\(tab.replacingOccurrences(of: "tab_", with: ""))",
        "Open the \(tab.replacingOccurrences(of: "tab_", with: "")) detail tab on the Dashboard", { tap(tab) })
}
step("dashboard", "start-all", "Click 'Start All' to start every configured service", { tap("start_all_btn") })
step("dashboard", "stop-all", "Click 'Stop' to stop running services", { tap("stop_all_btn") })

// Pass 3 — Discovery: filter + scan options
selectNav("nav_discovery")
Thread.sleep(forTimeInterval: settle)
step("discovery", "filter-api", "Type 'api' into the projects filter field", { typeIn("projects_filter", "api") })
step("discovery", "filter-clear", "Clear the projects filter", { typeIn("projects_filter", "") })
step("discovery", "force-rescan", "Click 'Force rescan' to re-scan for projects", { tap("scan_force_rescan") })
step("discovery", "scan-full-disk", "Toggle 'Scan full disk'", { tap("scan_full_disk") })

// Pass 4 — AI Chat: input + send
selectNav("nav_ai_chat")
Thread.sleep(forTimeInterval: settle)
step(
    "ai-chat", "type-question", "Type a question into the AI assistant input",
    { typeIn("ai_input", "optimize my postgres memory usage") })
step("ai-chat", "send", "Click send to submit the AI question", { tap("ai_send_button") })

// Pass 5 — revisit each remaining screen so its loaded content is captured standalone
for (id, screen) in [
    ("nav_connections", "connections"), ("nav_deploy", "deploy"), ("nav_tunnel", "tunnel"),
    ("nav_uninstall", "uninstall"), ("nav_settings", "settings"),
] {
    step(screen, "revisit", "Revisit the \(screen) screen to capture its loaded content", { selectNav(id) })
}

// MARK: - Write manifest + clean up
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
if let data = try? enc.encode(manifest) {
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/manifest.json"))
}
FileHandle.standardOutput.write(
    "wrote \(manifest.count) steps (\(manifest.count * 2) screenshots) to \(outDir)\n".data(using: .utf8)!)

proc.terminate()
proc.waitUntilExit()
