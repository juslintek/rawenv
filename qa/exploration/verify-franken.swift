// qa/exploration/verify-franken.swift
// Drives the SwiftUI app via the Accessibility API to set up a frankenphp
// project END TO END (scan -> Set Up -> Set Up Environment) and screenshot the
// result, proving the frankenphp web server starts THROUGH THE APP (not the CLI).
//
// Run:  swift verify-franken.swift <gui-binary> <output-dir> <project-name>

import AppKit
import Foundation

let argv = CommandLine.arguments
let binaryPath = argv.count > 1 ? argv[1] : "/tmp/vmbuild/debug/Rawenv"
let outDir = argv.count > 2 ? argv[2] : "\(NSHomeDirectory())/rawenv-franken"
let projectName = argv.count > 3 ? argv[3] : "demo-franken"
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
    guard d < 26 else { return nil }
    for c in axChildren(root) { if let f = findById(c, id, d + 1) { return f } }
    return nil
}
func axParentRow(_ root: AXUIElement, _ id: String, _ d: Int = 0) -> AXUIElement? {
    if axStr(root, kAXRoleAttribute) == "AXRow", findById(root, id) != nil { return root }
    guard d < 26 else { return nil }
    for c in axChildren(root) { if let f = axParentRow(c, id, d + 1) { return f } }
    return nil
}
func axText(_ e: AXUIElement) -> String {
    (axStr(e, kAXTitleAttribute) ?? "") + " " + (axStr(e, kAXDescriptionAttribute) ?? "") + " "
        + (axStr(e, kAXValueAttribute) ?? "")
}
func subtreeText(_ e: AXUIElement, _ d: Int = 0) -> String {
    var t = axText(e)
    if d < 8 { for c in axChildren(e) { t += " " + subtreeText(c, d + 1) } }
    return t
}
func findButton(_ root: AXUIElement, _ sub: String, _ d: Int = 0) -> AXUIElement? {
    if axStr(root, kAXRoleAttribute) == "AXButton", subtreeText(root).contains(sub) { return root }
    guard d < 26 else { return nil }
    for c in axChildren(root) { if let f = findButton(c, sub, d + 1) { return f } }
    return nil
}
// Smallest subtree containing `name` that also holds a "Set Up" button → that button.
func findSetUpFor(_ root: AXUIElement, _ name: String, _ d: Int = 0) -> AXUIElement? {
    if d < 26 { for c in axChildren(root) { if let f = findSetUpFor(c, name, d + 1) { return f } } }
    if subtreeText(root).contains(name), let b = findButton(root, "Set Up") { return b }
    return nil
}
func press(_ e: AXUIElement) { AXUIElementPerformAction(e, kAXPressAction as CFString) }

let proc = Process()
proc.executableURL = URL(fileURLWithPath: binaryPath)
proc.arguments = ["--ui-testing"]
try proc.run()
Thread.sleep(forTimeInterval: 3.5)
let app = AXUIElementCreateApplication(proc.processIdentifier)
NSRunningApplication(processIdentifier: proc.processIdentifier)?.activate(options: [])
Thread.sleep(forTimeInterval: 0.8)
func win() -> AXUIElement? { axWindows(app).first }

var seq = 0
func capture(_ label: String) {
    seq += 1
    let file = "\(outDir)/\(String(format: "%02d", seq))_\(label).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", file]
    try? p.run()
    p.waitUntilExit()
    FileHandle.standardOutput.write("shot \(seq): \(label)\n".data(using: .utf8)!)
}
@discardableResult func tapButton(_ sub: String) -> Bool {
    guard let w = win(), let e = findButton(w, sub) else { return false }
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
func waitWhile(_ id: String, _ sec: Double) {
    let deadline = Date().addingTimeInterval(sec)
    while Date() < deadline {
        if let w = win(), findById(w, id) == nil { return }
        Thread.sleep(forTimeInterval: 1.0)
    }
}

selectNav("nav_discovery")
Thread.sleep(forTimeInterval: 1.0)
tapButton("Force rescan")
Thread.sleep(forTimeInterval: 2.0)
_ = waitForId("scan_complete_banner", 60)
tapButton("View Projects")
Thread.sleep(forTimeInterval: 1.2)
capture("project-list")

if let w = win(), let b = findSetUpFor(w, projectName) {
    press(b)
    FileHandle.standardOutput.write("pressed Set Up for \(projectName)\n".data(using: .utf8)!)
} else {
    FileHandle.standardOutput.write("ERROR: no Set Up button found for \(projectName)\n".data(using: .utf8)!)
}
_ = waitForId("setup_generate_btn", 30)
Thread.sleep(forTimeInterval: 1.0)
capture("setup-detected")
tapButton("Set Up Environment")
Thread.sleep(forTimeInterval: 2.0)
waitWhile("setup_in_progress", 180)
Thread.sleep(forTimeInterval: 3.0)
capture("setup-result")

proc.terminate()
proc.waitUntilExit()
FileHandle.standardOutput.write("done\n".data(using: .utf8)!)
