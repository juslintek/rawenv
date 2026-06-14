import AppKit
import Foundation
import Testing

@testable import RawenvLib

// MARK: - UI E2E Tests using Accessibility APIs
//
// PREREQUISITES:
// 1. Build the app first: `swift build`
// 2. Grant Accessibility permissions to Terminal/IDE in:
//    System Settings → Privacy & Security → Accessibility
// 3. The app uses `--ui-testing` to skip installer and show dashboard directly.

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RAWENV_RUN_UI_E2E"] == "1"))
struct UIE2ETests {
    private let binaryPath =
        ProcessInfo.processInfo.environment["RAWENV_GUI_BINARY"]
        ?? "\(FileManager.default.currentDirectoryPath)/.build/debug/Rawenv"

    // MARK: - Helpers

    private func ensureBinaryExists() throws {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw AXTestError.binaryNotFound(binaryPath)
        }
    }

    private func launchApp() throws -> (Process, AXUIElement) {
        try ensureBinaryExists()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--ui-testing"]
        try process.run()
        Thread.sleep(forTimeInterval: 3)
        let app = AXUIElementCreateApplication(process.processIdentifier)
        return (process, app)
    }

    private func terminateApp(_ process: Process) {
        process.terminate()
        process.waitUntilExit()
    }

    private func getAttribute(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        return value
    }

    private func getStringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        getAttribute(element, attr) as? String
    }

    private func getChildren(_ element: AXUIElement) -> [AXUIElement] {
        (getAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private func getWindows(_ app: AXUIElement) -> [AXUIElement] {
        (getAttribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// Recursively find element by accessibility identifier
    private func findById(_ root: AXUIElement, _ id: String, depth: Int = 0) -> AXUIElement? {
        if getStringAttr(root, kAXIdentifierAttribute) == id { return root }
        guard depth < 15 else { return nil }
        for child in getChildren(root) {
            if let found = findById(child, id, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Find element by AXDescription attribute
    private func findByDescription(_ root: AXUIElement, _ desc: String, depth: Int = 0) -> AXUIElement? {
        if getStringAttr(root, kAXDescriptionAttribute) == desc { return root }
        guard depth < 15 else { return nil }
        for child in getChildren(root) {
            if let found = findByDescription(child, desc, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Find element by value
    private func findByValue(_ root: AXUIElement, _ value: String, depth: Int = 0) -> AXUIElement? {
        if getStringAttr(root, kAXValueAttribute) == value { return root }
        guard depth < 15 else { return nil }
        for child in getChildren(root) {
            if let found = findByValue(child, value, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Find all elements matching a predicate
    private func findAll(
        _ root: AXUIElement, depth: Int = 0, maxDepth: Int = 15, where predicate: (AXUIElement) -> Bool
    ) -> [AXUIElement] {
        var results: [AXUIElement] = []
        if predicate(root) { results.append(root) }
        guard depth < maxDepth else { return results }
        for child in getChildren(root) {
            results += findAll(child, depth: depth + 1, maxDepth: maxDepth, where: predicate)
        }
        return results
    }

    private func clickElement(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// Find the AXRow that contains an element with the given identifier
    private func findParentRow(_ root: AXUIElement, containingId id: String, depth: Int = 0) -> AXUIElement? {
        if getStringAttr(root, kAXRoleAttribute) == "AXRow" {
            if findById(root, id, depth: 0) != nil { return root }
        }
        guard depth < 15 else { return nil }
        for child in getChildren(root) {
            if let found = findParentRow(child, containingId: id, depth: depth + 1) { return found }
        }
        return nil
    }

    // MARK: - Tests

    @Test func windowExists() throws {
        let (process, app) = try launchApp()
        defer { terminateApp(process) }

        let windows = getWindows(app)
        #expect(!windows.isEmpty, "App should have at least one window")

        let title = getStringAttr(app, kAXTitleAttribute)
        #expect(title == "Rawenv", "App title should be 'Rawenv'")
    }

    @Test func sidebarNavigationItemsExist() throws {
        let (process, app) = try launchApp()
        defer { terminateApp(process) }

        let windows = getWindows(app)
        guard let window = windows.first else {
            Issue.record("No window found")
            return
        }

        let navIds = [
            "nav_dashboard", "nav_discovery", "nav_ai_chat",
            "nav_connections", "nav_deploy", "nav_tunnel",
            "nav_uninstall", "nav_settings",
        ]

        var found: [String] = []
        for id in navIds where findById(window, id) != nil {
            found.append(id)
        }

        #expect(found.count == 8, "Should find all 8 nav items, found \(found.count): \(found)")
    }

    @Test func dashboardViewVisible() throws {
        let (process, app) = try launchApp()
        defer { terminateApp(process) }

        let windows = getWindows(app)
        guard let window = windows.first else {
            Issue.record("No window found")
            return
        }

        // dashboard_view identifier is present on elements in the detail area
        let dashboard = findById(window, "dashboard_view")
        #expect(dashboard != nil, "Dashboard view should be visible on launch")
    }

    @Test func statsCardsShowLabels() throws {
        let (process, app) = try launchApp()
        defer { terminateApp(process) }

        let windows = getWindows(app)
        guard let window = windows.first else {
            Issue.record("No window found")
            return
        }

        // Stats cards expose their labels as AXStaticText with value
        let cpuLabel = findByValue(window, "CPU")
        let memLabel = findByValue(window, "Memory")
        let runLabel = findByValue(window, "Running")

        #expect(cpuLabel != nil, "CPU stats label should exist")
        #expect(memLabel != nil, "Memory stats label should exist")
        #expect(runLabel != nil, "Running stats label should exist")
    }

    @Test func dashboardTabsExist() throws {
        let (process, app) = try launchApp()
        defer { terminateApp(process) }

        let windows = getWindows(app)
        guard let window = windows.first else {
            Issue.record("No window found")
            return
        }

        // Tab buttons are AXButton with AXDescription matching tab names
        let tabNames = ["Logs", "Config", "Connection", "Cell", "Backups"]
        var found: [String] = []
        for name in tabNames where findByDescription(window, name) != nil {
            found.append(name)
        }

        #expect(found.count == 5, "Should find all 5 tabs, found \(found.count): \(found)")
    }

    @Test func navigationChangesDetailView() throws {
        let (process, app) = try launchApp()
        defer { terminateApp(process) }

        let windows = getWindows(app)
        guard let window = windows.first else {
            Issue.record("No window found")
            return
        }

        guard let sidebar = findById(window, "sidebar") else {
            Issue.record("Sidebar not found")
            return
        }

        // Navigate to AI Chat by selecting its row in the outline
        guard let aiChatRow = findParentRow(window, containingId: "nav_ai_chat") else {
            Issue.record("AI Chat row not found")
            return
        }

        let rowArray = [aiChatRow] as CFArray
        AXUIElementSetAttributeValue(sidebar, "AXSelectedRows" as CFString, rowArray)
        Thread.sleep(forTimeInterval: 1)

        // Logs tab should not be visible after navigating away from Dashboard
        let logsTab = findByDescription(window, "Logs")
        #expect(logsTab == nil, "Logs tab should not be visible after navigating to AI Chat")

        // Navigate back to Dashboard
        guard let dashRow = findParentRow(window, containingId: "nav_dashboard") else {
            Issue.record("Dashboard row not found")
            return
        }
        let dashArray = [dashRow] as CFArray
        AXUIElementSetAttributeValue(sidebar, "AXSelectedRows" as CFString, dashArray)
        Thread.sleep(forTimeInterval: 1)

        let logsTabAgain = findByDescription(window, "Logs")
        #expect(logsTabAgain != nil, "Logs tab should be visible after navigating back to Dashboard")
    }

    @Test func sidebarExists() throws {
        let (process, app) = try launchApp()
        defer { terminateApp(process) }

        let windows = getWindows(app)
        guard let window = windows.first else {
            Issue.record("No window found")
            return
        }

        let sidebar = findById(window, "sidebar")
        #expect(sidebar != nil, "Sidebar outline should exist")
    }

    @Test func startStopButtonsExist() throws {
        let (process, app) = try launchApp()
        defer { terminateApp(process) }

        let windows = getWindows(app)
        guard let window = windows.first else {
            Issue.record("No window found")
            return
        }

        let startBtn = findById(window, "start_all_btn")
        let stopBtn = findById(window, "stop_all_btn")

        #expect(startBtn != nil, "Start All button should exist in sidebar")
        #expect(stopBtn != nil, "Stop button should exist in sidebar")
    }
}

// MARK: - Error Types

enum AXTestError: Error, CustomStringConvertible {
    case binaryNotFound(String)

    var description: String {
        switch self {
        case .binaryNotFound(let path):
            return "Binary not found at \(path). Run `swift build` first."
        }
    }
}
