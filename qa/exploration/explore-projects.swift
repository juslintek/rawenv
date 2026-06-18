// qa/exploration/explore-projects.swift
// Screenshots the full Discovered Projects list (all mounted real projects) and drives the
// project Setup view for VM-LOCAL demo projects representing each outcome — success (node+redis),
// unsupported (rust), and partial (node ok + mysql unavailable on macOS) — capturing the version
// picker and the install result/error UX. Uses VM-local demos so the user's REAL mounted projects
// are never mutated (GUI detect() runs `rawenv init`, which writes rawenv.toml into the project).
//
// Run:  swift explore-projects.swift <gui-binary> <output-dir>

import AppKit
import Foundation

let argv = CommandLine.arguments
let binaryPath = argv.count > 1 ? argv[1] : "/tmp/vmbuild/debug/Rawenv"
let outDir = argv.count > 2 ? argv[2] : "\(NSHomeDirectory())/rawenv-projects"
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
func axText(_ e: AXUIElement) -> String {
    (axStr(e, kAXTitleAttribute) ?? "") + " " + (axStr(e, kAXDescriptionAttribute) ?? "") + " "
        + (axStr(e, kAXValueAttribute) ?? "")
}
func subtreeText(_ e: AXUIElement, _ d: Int = 0) -> String {
    var t = axText(e)
    if d < 6 { for c in axChildren(e) { t += " " + subtreeText(c, d + 1) } }
    return t
}
func findButton(_ root: AXUIElement, _ sub: String, _ d: Int = 0) -> AXUIElement? {
    if axStr(root, kAXRoleAttribute) == "AXButton", subtreeText(root).contains(sub) { return root }
    guard d < 24 else { return nil }
    for c in axChildren(root) { if let f = findButton(c, sub, d + 1) { return f } }
    return nil
}
func press(_ e: AXUIElement) { AXUIElementPerformAction(e, kAXPressAction as CFString) }
func setVal(_ e: AXUIElement, _ v: String) {
    AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, v as CFString)
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
var seq = 199  // project-setup catalog = 200+

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
    FileHandle.standardOutput.write("shot \(n): \(screen)/\(action)\n".data(using: .utf8)!)
}
@discardableResult func tapButton(_ sub: String) -> Bool {
    guard let w = win(), let e = findButton(w, sub) else { return false }
    press(e)
    return true
}
func tapId(_ id: String) { if let w = win(), let e = findById(w, id) { press(e) } }
func typeId(_ id: String, _ v: String) { if let w = win(), let e = findById(w, id) { setVal(e, v) } }
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
func waitWhile(_ id: String, _ sec: Double) {
    let deadline = Date().addingTimeInterval(sec)
    while Date() < deadline {
        if let w = win(), findById(w, id) == nil { return }
        Thread.sleep(forTimeInterval: 1.0)
    }
}

// Scan + open the project list.
selectNav("nav_discovery")
Thread.sleep(forTimeInterval: 1.0)
tapButton("Force rescan")
Thread.sleep(forTimeInterval: 2.0)
_ = waitForId("scan_complete_banner", 60)
capture("discovery", "scan-all-projects", "Scan of the mounted projects volume (all real projects) complete")
tapButton("View Projects")
Thread.sleep(forTimeInterval: 1.2)
capture(
    "projects", "discovered-list",
    "Full Discovered Projects list — all real projects found via the mounted projects volume")

// Drive setup for VM-local demos: success / unsupported / partial.
func driveSetup(_ name: String, _ desc: String, openPicker: Bool) {
    typeId("projects_filter", name)
    Thread.sleep(forTimeInterval: 0.8)
    capture("projects", "filter-\(name)", "Filtered project list to \(name)")
    guard tapButton("Set Up") else {
        capture("projects", "\(name)-no-setup-btn", "Could not find Set Up button for \(name)")
        return
    }
    _ = waitForId("setup_back_btn", 8)
    _ = waitForId("setup_generate_btn", 30)
    Thread.sleep(forTimeInterval: 1.0)
    capture("setup", "\(name)-detected", "Setup view — detected stack for \(name): \(desc)")
    if openPicker, let w = win(), let pk = findById(w, "setup_node_version") {
        press(pk)
        Thread.sleep(forTimeInterval: 0.8)
        capture("setup", "\(name)-version-picker", "Node version picker opened on the setup view for \(name)")
        press(pk)
        Thread.sleep(forTimeInterval: 0.4)
    }
    tapButton("Set Up Environment")
    Thread.sleep(forTimeInterval: 2.0)
    waitWhile("setup_in_progress", 180)
    Thread.sleep(forTimeInterval: 1.5)
    capture("setup", "\(name)-result", "After 'Set Up Environment' for \(name) — install result/error")
    tapButton("Back to projects")
    Thread.sleep(forTimeInterval: 0.6)
    typeId("projects_filter", "")
    Thread.sleep(forTimeInterval: 0.6)
}

driveSetup("demo-node", "node 22 + redis 7 (fully installable)", openPicker: true)
driveSetup("demo-rust", "rust (NOT an installable package → expect error)", openPicker: false)
driveSetup("demo-mysql", "node 22 + mysql 8 (mysql has no macOS binary → expect partial)", openPicker: false)

let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
do {
    let d = try enc.encode(manifest)
    try d.write(to: URL(fileURLWithPath: "\(outDir)/manifest-projects.json"))
} catch {
    FileHandle.standardError.write("Error: could not write manifest: \(error)\n".data(using: .utf8)!)
}
FileHandle.standardOutput.write("wrote \(manifest.count) project-setup shots to \(outDir)\n".data(using: .utf8)!)
proc.terminate()
proc.waitUntilExit()
