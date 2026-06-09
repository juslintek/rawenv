import Testing
import Foundation
import AppKit
@testable import RawenvLib

// MARK: - Comprehensive Screen-Hijacking UI E2E
//
// Drives EVERY screen, tab, button, text field, picker option, and toggle in the
// real Rawenv.app via the Accessibility (AX) API. This LAUNCHES THE APP AND TAKES
// OVER THE SCREEN (moves focus, opens menus). Run it on an idle machine or, ideally,
// inside the Tart VM — never while you need the host.
//
// Prereqs: `swift build` (debug app at .build/debug/Rawenv) + Accessibility
// permission granted to the running terminal/IDE.

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RAWENV_RUN_UI_E2E"] == "1"))
struct ComprehensiveUIE2ETests {
    private let binaryPath = "/Volumes/Projects/rawenv/gui/macos/.build/debug/Rawenv"
    private let settle: TimeInterval = 0.4

    // MARK: AX primitives

    private func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
        var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v
    }
    private func str(_ e: AXUIElement, _ a: String) -> String? { attr(e, a) as? String }
    private func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
    private func windows(_ app: AXUIElement) -> [AXUIElement] { (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }

    private func findById(_ root: AXUIElement, _ id: String, _ depth: Int = 0) -> AXUIElement? {
        if str(root, kAXIdentifierAttribute) == id { return root }
        guard depth < 18 else { return nil }
        for c in children(root) { if let f = findById(c, id, depth + 1) { return f } }
        return nil
    }
    private func findAll(_ root: AXUIElement, _ depth: Int = 0, _ pred: (AXUIElement) -> Bool) -> [AXUIElement] {
        var r: [AXUIElement] = []
        if pred(root) { r.append(root) }
        guard depth < 18 else { return r }
        for c in children(root) { r += findAll(c, depth + 1, pred) }
        return r
    }
    private func findAllByPrefix(_ root: AXUIElement, _ prefix: String) -> [AXUIElement] {
        findAll(root) { (str($0, kAXIdentifierAttribute) ?? "").hasPrefix(prefix) }
    }
    private func press(_ e: AXUIElement) { AXUIElementPerformAction(e, kAXPressAction as CFString) }
    private func setValue(_ e: AXUIElement, _ v: String) { AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, v as CFString) }

    private func parent(_ e: AXUIElement) -> AXUIElement? {
        guard let p = attr(e, kAXParentAttribute) else { return nil }
        return (p as! AXUIElement)
    }
    /// True if the element lives under the macOS menu bar (Apple/File/Edit/Window/Help…).
    /// Pressing those items opens Help Viewer and stray windows — we must never touch them.
    private func underMenuBar(_ e: AXUIElement) -> Bool {
        var cur: AXUIElement? = e, hops = 0
        while let c = cur, hops < 14 {
            if str(c, kAXRoleAttribute) == "AXMenuBar" { return true }
            cur = parent(c); hops += 1
        }
        return false
    }
    /// Option items of an OPEN popup picker — strictly excluding the menu bar.
    private func popupOptions(_ app: AXUIElement) -> [AXUIElement] {
        findAll(app) { str($0, kAXRoleAttribute) == "AXMenuItem" && !underMenuBar($0) }
    }

    private func parentRow(_ root: AXUIElement, containing id: String, _ depth: Int = 0) -> AXUIElement? {
        if str(root, kAXRoleAttribute) == "AXRow", findById(root, id) != nil { return root }
        guard depth < 18 else { return nil }
        for c in children(root) { if let f = parentRow(c, containing: id, depth + 1) { return f } }
        return nil
    }

    // MARK: high-level actions

    private func launch() throws -> (Process, AXUIElement) {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { throw AXTestError.binaryNotFound(binaryPath) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: binaryPath); p.arguments = ["--ui-testing"]
        try p.run(); Thread.sleep(forTimeInterval: 3)
        return (p, AXUIElementCreateApplication(p.processIdentifier))
    }

    /// Select a row in any List/outline (sidebar or settings_sidebar) by the id it contains.
    private func selectRow(_ window: AXUIElement, list listId: String, containing id: String) {
        guard let list = findById(window, listId), let row = parentRow(window, containing: id) else { return }
        AXUIElementSetAttributeValue(list, "AXSelectedRows" as CFString, [row] as CFArray)
        Thread.sleep(forTimeInterval: settle)
    }
    private func tap(_ window: AXUIElement, _ id: String) {
        if let e = findById(window, id) { press(e); Thread.sleep(forTimeInterval: settle) }
    }
    /// Poll for an element to appear (handles view render timing after navigation).
    @discardableResult
    private func waitForId(_ window: AXUIElement, _ id: String, _ seconds: Double = 3) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let e = findById(window, id) { return e }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }
    private func type(_ window: AXUIElement, _ id: String, _ value: String) {
        if let e = findById(window, id) { setValue(e, value); Thread.sleep(forTimeInterval: settle) }
    }
    /// Open a picker and select every option in turn (exercises every configuration).
    /// Only presses items inside the picker's own popup — never the macOS menu bar.
    private func cyclePicker(_ app: AXUIElement, _ window: AXUIElement, _ id: String) {
        guard let picker = findById(window, id) else { return }
        press(picker); Thread.sleep(forTimeInterval: settle)
        let count = popupOptions(app).count
        press(picker); Thread.sleep(forTimeInterval: 0.2) // close
        guard count > 0 else { return }
        for i in 0..<count {
            guard let pk = findById(window, id) else { break }
            press(pk); Thread.sleep(forTimeInterval: settle)
            let opts = popupOptions(app)
            guard !opts.isEmpty else { break }      // picker didn't open — bail, don't poke elsewhere
            press(opts[min(i, opts.count - 1)])     // selecting an item closes the popup
            Thread.sleep(forTimeInterval: settle)
        }
    }
    /// Press every checkbox (SwiftUI Toggle) currently on screen, then press again to restore.
    private func toggleAll(_ window: AXUIElement) {
        let boxes = findAll(window) { str($0, kAXRoleAttribute) == "AXCheckBox" }
        for b in boxes { press(b); Thread.sleep(forTimeInterval: 0.1) }
        for b in boxes { press(b); Thread.sleep(forTimeInterval: 0.1) } // restore
    }

    // MARK: - The full flow

    @Test func fullFlowEveryControlAndOption() throws {
        let (proc, app) = try launch()
        defer { proc.terminate(); proc.waitUntilExit() }
        guard let window = windows(app).first else { Issue.record("no window"); return }

        // ---- Dashboard: every tab + start/stop + service rows ----
        selectRow(window, list: "sidebar", containing: "nav_dashboard")
        #expect(findById(window, "dashboard_view") != nil, "dashboard visible")
        for tab in ["tab_logs", "tab_config", "tab_connection", "tab_cell", "tab_backups"] { tap(window, tab) }
        tap(window, "start_all_btn")
        tap(window, "stop_all_btn")
        for svc in findAllByPrefix(window, "service_") { press(svc); Thread.sleep(forTimeInterval: 0.15) }

        // ---- Discovery: filter + every scan option + project setup buttons ----
        selectRow(window, list: "sidebar", containing: "nav_discovery")
        #expect(findById(window, "projects_view") != nil, "discovery visible")
        type(window, "projects_filter", "api")
        type(window, "projects_filter", "")
        tap(window, "scan_force_rescan")
        tap(window, "scan_full_disk")
        for btn in findAllByPrefix(window, "project_setup_btn_") { press(btn); Thread.sleep(forTimeInterval: 0.15) }

        // ---- AI Chat: provider picker (every option) + input + send ----
        selectRow(window, list: "sidebar", containing: "nav_ai_chat")
        #expect(findById(window, "ai_chat_view") != nil, "ai chat visible")
        cyclePicker(app, window, "ai_provider_picker")
        type(window, "ai_input", "optimize my postgres memory usage")
        tap(window, "ai_send_button")

        // ---- Connections: toggle local/proxy/remote for every connection ----
        selectRow(window, list: "sidebar", containing: "nav_connections")
        #expect(findById(window, "connections_view") != nil, "connections visible")
        for mode in ["conn_local_", "conn_proxy_", "conn_remote_"] {
            for e in findAllByPrefix(window, mode) { press(e); Thread.sleep(forTimeInterval: 0.15) }
        }

        // ---- Deploy: every tab + generate + ai fix ----
        selectRow(window, list: "sidebar", containing: "nav_deploy")
        #expect(findById(window, "deploy_view") != nil, "deploy visible")
        for tab in ["deploy_tab_terraform", "deploy_tab_ansible", "deploy_tab_containerfile", "deploy_tab_deployLog"] { tap(window, tab) }
        tap(window, "deploy_start_button")
        tap(window, "deploy_ai_fix")

        // ---- Tunnel: port + relay + provider (every option) + create ----
        selectRow(window, list: "sidebar", containing: "nav_tunnel")
        #expect(findById(window, "tunnel_view") != nil, "tunnel visible")
        type(window, "tunnel_port_input", "8080")
        type(window, "tunnel_relay_input", "bore.pub")
        cyclePicker(app, window, "tunnel_provider_picker")
        tap(window, "tunnel_create_button")

        // ---- Settings: every page, every toggle, every picker option, fields, theme ----
        selectRow(window, list: "sidebar", containing: "nav_settings")
        // settings_view sits on an HSplitView (AXSplitGroup) whose id SwiftUI doesn't
        // reliably expose; the settings_sidebar List is the reliable "settings visible" signal.
        #expect(waitForId(window, "settings_sidebar") != nil, "settings visible")
        let pages = ["general", "services", "runtimes", "network", "cells", "deploy", "ai", "theme", "about"]
        for page in pages {
            selectRow(window, list: "settings_sidebar", containing: "settings_page_\(page)")
            toggleAll(window)
            // page-specific pickers / fields / buttons
            switch page {
            case "network": cyclePicker(app, window, "settings_tunnel_provider_picker")
            case "deploy":
                cyclePicker(app, window, "settings_deploy_provider_picker")
                cyclePicker(app, window, "settings_container_runtime_picker")
            case "ai":
                cyclePicker(app, window, "ai_provider_picker")
                for pk in findAllByPrefix(window, "autonomy_") {
                    if let id = str(pk, kAXIdentifierAttribute) { cyclePicker(app, window, id) }
                }
                type(window, "byom_api_key", "test-key-123")
                type(window, "byom_endpoint", "http://localhost:11434")
            case "theme":
                cyclePicker(app, window, "theme_mode_picker")
                tap(window, "theme_reset_btn")
            case "about":
                tap(window, "reset_first_run_btn")
            default: break
            }
        }

        // ---- Uninstall: open the flow, then CANCEL (never actually uninstall) ----
        selectRow(window, list: "sidebar", containing: "nav_uninstall")
        #expect(findById(window, "uninstall_view") != nil, "uninstall visible")
        tap(window, "uninstall_button")
        tap(window, "uninstall_cancel")

        // Back to a safe screen.
        selectRow(window, list: "sidebar", containing: "nav_dashboard")
        #expect(findById(window, "dashboard_view") != nil, "returned to dashboard")
    }
}
