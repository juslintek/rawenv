// qa/exploration/explore-setup.swift
// Drives the FULL rawenv value loop on a real project and screenshots each stage:
//   Discovery scan -> View Projects -> Set Up Environment (detect) -> install
//   runtimes+services -> start -> verify running on the Dashboard.
// Precondition (set up by the caller in the VM):
//   ~/Projects/demo-node/{package.json (node 22), .env (REDIS_URL)}  -> detects node + redis
//   ~/.rawenv/bin/rawenv present (the CLI the GUI shells out to)
//
// Run:  swift explore-setup.swift <gui-binary> <output-dir> <project-name>

import AppKit
import Foundation

let argv = CommandLine.arguments
let binaryPath = argv.count > 1 ? argv[1] : "/tmp/vmbuild/debug/Rawenv"
let outDir = argv.count > 2 ? argv[2] : "\(NSHomeDirectory())/rawenv-setup"
let projectName = argv.count > 3 ? argv[3] : "demo-node"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(e, a as CFString, &v)
    return v
}
func axStr(_ e: AXUIElement, _ a: String) -> String? { attr(e, a) as? String }
func axChildren(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func axWindows(_ app: AXUIElement) -> [AXUIElement] { (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }
func findById(_ root: AXUIElement, _ id: String, _ d: Int = 0) -> AXUIElement? {
    if axStr(root, kAXIdentifierAttribute) == id { return root }
    guard d < 24 else { return nil }
    for c in axChildren(root) { if let f = findById(c, id, d + 1) { return f } }
    return nil
}
func axParentRow(_ root: AXUIElement, _ id: String, _ d: Int = 0) -> AXUIElement? {
    if axStr(root, kAXRoleAttribute) == "AXRow", findById(root, id) != nil { return root }
    guard d < 24 else { return nil }
    for c in axChildren(root) { if let f = axParentRow(c, id, d + 1) { return f } }
    return nil
}
func press(_ e: AXUIElement) { AXUIElementPerformAction(e, kAXPressAction as CFString) }

guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
    FileHandle.standardError.write("binary not found: \(binaryPath)\n".data(using: .utf8)!)
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
func win() -> AXUIElement? { axWindows(app).first }

struct Entry: Codable {
    let step: Int
    let screen: String
    let action: String
    let description: String
    let file: String
}
var manifest: [Entry] = []
var seq = 99  // continue after pass-1 (1..26); setup flow = 100+

func capture(_ screen: String, _ action: String, _ desc: String) {
    seq += 1
    let n = String(format: "%03d", seq)
    let file = "\(n)_\(screen)_\(action.replacingOccurrences(of: " ", with: "-")).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "\(outDir)/\(file)"]
    try? p.run()
    p.waitUntilExit()
    manifest.append(Entry(step: seq, screen: screen, action: action, description: desc, file: file))
    FileHandle.standardOutput.write("shot \(n): \(screen) / \(action)\n".data(using: .utf8)!)
}
func tap(_ id: String) -> Bool {
    guard let w = win(), let e = findById(w, id) else { return false }
    press(e)
    return true
}
func selectNav(_ id: String) {
    guard let w = win(), let list = findById(w, "sidebar"), let row = axParentRow(w, id) else { return }
    AXUIElementSetAttributeValue(list, "AXSelectedRows" as CFString, [row] as CFArray)
}
@discardableResult func waitForId(_ id: String, _ sec: Double) -> Bool {
    let deadline = Date().addingTimeInterval(sec)
    while Date() < deadline {
        if let w = win(), findById(w, id) != nil { return true }
        Thread.sleep(forTimeInterval: 0.4)
    }
    return false
}
/// Wait while an element is present (e.g. setup_in_progress) — returns when gone or timeout.
func waitWhile(_ id: String, _ sec: Double) {
    let deadline = Date().addingTimeInterval(sec)
    while Date() < deadline {
        if let w = win(), findById(w, id) == nil { return }
        Thread.sleep(forTimeInterval: 1.0)
    }
}
// Some buttons (e.g. the scan-complete "View Projects") lack an accessibility id,
// so locate them by visible text within an AXButton subtree.
func axText(_ e: AXUIElement) -> String {
    (axStr(e, kAXTitleAttribute) ?? "") + " " + (axStr(e, kAXDescriptionAttribute) ?? "") + " "
        + (axStr(e, kAXValueAttribute) ?? "")
}
func subtreeText(_ e: AXUIElement, _ d: Int = 0) -> String {
    var t = axText(e)
    if d < 6 { for c in axChildren(e) { t += " " + subtreeText(c, d + 1) } }
    return t
}
func findButtonContaining(_ root: AXUIElement, _ sub: String, _ d: Int = 0) -> AXUIElement? {
    if axStr(root, kAXRoleAttribute) == "AXButton", subtreeText(root).contains(sub) { return root }
    guard d < 24 else { return nil }
    for c in axChildren(root) { if let f = findButtonContaining(c, sub, d + 1) { return f } }
    return nil
}
@discardableResult func tapButtonText(_ sub: String) -> Bool {
    guard let w = win(), let e = findButtonContaining(w, sub) else { return false }
    press(e)
    return true
}

// ---- The full value loop ----
capture("launch", "initial", "App launched (--ui-testing); initial window")

selectNav("nav_discovery")
Thread.sleep(forTimeInterval: 1.0)
capture("discovery", "before-rescan", "Discovery screen before forcing a rescan")
_ = tapButtonText("Force rescan")
Thread.sleep(forTimeInterval: 1.5)
let scanned = waitForId("scan_complete_banner", 40)
capture("discovery", "scan-complete", "After Force rescan — scan complete (banner present: \(scanned))")

// Buttons: press the real AXButton by its text (ids resolve to non-pressable wrappers).
let toList = tapButtonText("View Projects")
let listShown = waitForId("project_setup_btn_\(projectName)", 10)
Thread.sleep(forTimeInterval: 0.8)
capture(
    "projects", "project-list",
    "Project list after View Projects (clicked=\(toList), \(projectName) visible=\(listShown))")

// "Set Up →" for the first project (demo-node).
let openedSetup = tapButtonText("Set Up")
let onSetup = waitForId("setup_back_btn", 8)
let detected = waitForId("setup_generate_btn", 30)
Thread.sleep(forTimeInterval: 1.0)
capture(
    "setup", "detected",
    "Setup view for \(projectName): detected stack (opened=\(openedSetup), onSetup=\(onSetup), detected=\(detected))")

// Set Up Environment -> install runtimes + services + up
let started = tapButtonText("Set Up Environment")
Thread.sleep(forTimeInterval: 2.0)
capture("setup", "installing", "Just clicked 'Set Up Environment' (start=\(started)) — install in progress")
waitWhile("setup_in_progress", 240)  // node + redis download/install can take a while
Thread.sleep(forTimeInterval: 1.5)
capture("setup", "install-complete", "After Set Up Environment finished (or timed out)")

// Verify on the Dashboard
selectNav("nav_dashboard")
Thread.sleep(forTimeInterval: 1.2)
capture("dashboard", "after-setup", "Dashboard after setting up \(projectName)")
_ = tapButtonText("Start All")
Thread.sleep(forTimeInterval: 4.0)
capture("dashboard", "after-start-all", "Dashboard after clicking Start All — checking running services")
for tab in ["tab_logs", "tab_config"] {
    _ = tap(tab)
    Thread.sleep(forTimeInterval: 0.8)
    capture("dashboard", "tab-\(tab.replacingOccurrences(of: "tab_", with: ""))", "Dashboard \(tab) after setup")
}

let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
if let d = try? enc.encode(manifest) { try? d.write(to: URL(fileURLWithPath: "\(outDir)/manifest-setup.json")) }
FileHandle.standardOutput.write("wrote \(manifest.count) setup-flow shots to \(outDir)\n".data(using: .utf8)!)
proc.terminate()
proc.waitUntilExit()
