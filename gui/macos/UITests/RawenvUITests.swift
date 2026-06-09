import XCTest

@MainActor
final class RawenvUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        if !app.staticTexts["nav_dashboard"].waitForExistence(timeout: 3) {
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(
                app.staticTexts["nav_dashboard"].waitForExistence(timeout: 5),
                "App window did not open"
            )
        }
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Helpers

    private func navigateTo(_ identifier: String) {
        let navItem = app.staticTexts[identifier]
        XCTAssertTrue(navItem.waitForExistence(timeout: 3), "Nav item \(identifier) not found")
        navItem.tap()
        sleep(2)
    }

    private func elementExists(_ identifier: String, timeout: TimeInterval = 10) -> Bool {
        let pred = NSPredicate(format: "identifier == %@", identifier)
        let query = app.descendants(matching: .any).matching(pred)
        return query.firstMatch.waitForExistence(timeout: timeout)
    }

    // MARK: - Navigation Tests

    func testDashboardIsDefaultScreen() {
        XCTAssertTrue(elementExists("dashboard_view"))
        XCTAssertTrue(app.staticTexts["CPU"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Memory"].exists)
        XCTAssertTrue(app.staticTexts["Running"].exists)
    }

    func testNavigateToDiscovery() {
        navigateTo("nav_discovery")
        XCTAssertTrue(elementExists("projects_view") || elementExists("scan_complete_banner"))
    }

    func testNavigateToAIChat() {
        navigateTo("nav_ai_chat")
        XCTAssertTrue(elementExists("ai_chat_view"))
    }

    func testNavigateToConnections() {
        navigateTo("nav_connections")
        XCTAssertTrue(elementExists("connections_view"))
    }

    func testNavigateToDeploy() {
        navigateTo("nav_deploy")
        XCTAssertTrue(elementExists("deploy_view"))
        XCTAssertTrue(app.buttons["Terraform"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Ansible"].exists)
        XCTAssertTrue(app.buttons["Image"].exists)
        XCTAssertTrue(app.buttons["Deploy Log"].exists)
    }

    func testNavigateToTunnel() {
        navigateTo("nav_tunnel")
        XCTAssertTrue(elementExists("tunnel_view"))
    }

    func testNavigateToSettings() {
        navigateTo("nav_settings")
        XCTAssertTrue(elementExists("settings_view") || elementExists("settings_sidebar"))
    }

    func testNavigateToUninstall() {
        navigateTo("nav_uninstall")
        XCTAssertTrue(elementExists("uninstall_view"))
    }

    // MARK: - Dashboard Interaction

    func testDashboardTabSwitching() {
        let tabs = ["logs", "config", "connection", "cell", "backups"]
        for tab in tabs {
            let button = app.buttons["tab_\(tab)"]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                sleep(1)
            }
        }
    }

    func testStartStopButtons() {
        XCTAssertTrue(app.buttons["start_all_btn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stop_all_btn"].exists)
    }

    // MARK: - Deploy Tab Switching

    func testDeployTabSwitching() {
        navigateTo("nav_deploy")
        XCTAssertTrue(app.buttons["Terraform"].waitForExistence(timeout: 5))
        app.buttons["Ansible"].tap()
        sleep(1)
        app.buttons["Image"].tap()
        sleep(1)
        app.buttons["Deploy Log"].tap()
        sleep(1)
    }

    // MARK: - Tunnel Creation

    func testTunnelCreation() {
        navigateTo("nav_tunnel")
        let portField = app.textFields["tunnel_port_input"]
        XCTAssertTrue(portField.waitForExistence(timeout: 5))
        portField.tap()
        portField.typeText("8080")
        app.buttons["tunnel_create_button"].tap()
        sleep(2)
        XCTAssertTrue(
            elementExists("tunnel_entry_8080") || app.buttons["Stop"].exists,
            "Tunnel entry not created"
        )
    }

    // MARK: - Settings Pages

    func testSettingsAllPages() {
        navigateTo("nav_settings")
        XCTAssertTrue(elementExists("settings_view") || elementExists("settings_sidebar"))
        let pages = ["general", "services", "runtimes", "network", "cells", "deploy", "ai", "theme", "about"]
        for page in pages {
            let pageItem = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@", "settings_page_\(page)")
            ).firstMatch
            if pageItem.waitForExistence(timeout: 3) {
                pageItem.tap()
                sleep(1)
            }
        }
    }

    // MARK: - Full Navigation Round Trip

    func testFullNavigationRoundTrip() {
        let screens: [(nav: String, verify: [String])] = [
            ("nav_discovery", ["projects_view"]),
            ("nav_ai_chat", ["ai_chat_view"]),
            ("nav_connections", ["connections_view"]),
            ("nav_deploy", ["deploy_view"]),
            ("nav_tunnel", ["tunnel_view"]),
            ("nav_uninstall", ["uninstall_view"]),
            ("nav_settings", ["settings_view", "settings_sidebar"]),
            ("nav_dashboard", ["dashboard_view"]),
        ]
        for screen in screens {
            navigateTo(screen.nav)
            let found = screen.verify.contains { elementExists($0) }
            XCTAssertTrue(found, "Failed to navigate to \(screen.nav) — expected one of \(screen.verify)")
        }
    }

    // MARK: - Full Lifecycle Flow

    func testCompleteLifecycleFlow() {
        // 1. Dashboard loads
        XCTAssertTrue(elementExists("dashboard_view"))

        // 2. Dashboard tabs
        for tab in ["logs", "config", "connection", "cell", "backups"] {
            let btn = app.buttons["tab_\(tab)"]
            if btn.waitForExistence(timeout: 2) { btn.tap(); sleep(1) }
        }

        // 3. Discovery
        navigateTo("nav_discovery")
        XCTAssertTrue(elementExists("projects_view"))

        // 4. AI Chat
        navigateTo("nav_ai_chat")
        XCTAssertTrue(elementExists("ai_chat_view"))

        // 5. Connections
        navigateTo("nav_connections")
        XCTAssertTrue(elementExists("connections_view"))

        // 6. Deploy + tab switching
        navigateTo("nav_deploy")
        XCTAssertTrue(elementExists("deploy_view"))
        for tab in ["deploy_tab_terraform", "deploy_tab_ansible", "deploy_tab_containerfile", "deploy_tab_deployLog"] {
            let btn = app.buttons[tab]
            if btn.waitForExistence(timeout: 3) { btn.tap(); sleep(1) }
        }

        // 7. Tunnel
        navigateTo("nav_tunnel")
        XCTAssertTrue(elementExists("tunnel_view"))

        // 8. Uninstall
        navigateTo("nav_uninstall")
        XCTAssertTrue(elementExists("uninstall_view"))

        // 9. Settings + all pages
        navigateTo("nav_settings")
        XCTAssertTrue(elementExists("settings_view") || elementExists("settings_sidebar"))
        for page in ["general", "services", "runtimes", "network", "cells", "deploy", "ai", "theme", "about"] {
            let item = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@", "settings_page_\(page)")
            ).firstMatch
            if item.waitForExistence(timeout: 2) { item.tap(); sleep(1) }
        }

        // 10. Back to Dashboard
        navigateTo("nav_dashboard")
        XCTAssertTrue(elementExists("dashboard_view"))
    }

    // MARK: - Project Setup Flow

    func testProjectSetupFlow() {
        // 1. Start on Dashboard
        XCTAssertTrue(elementExists("dashboard_view"))

        // 2. Go to Discovery, wait for scan
        navigateTo("nav_discovery")
        XCTAssertTrue(elementExists("projects_view"))
        sleep(3) // Wait for scan animation to complete

        // 3. Click "View Projects" if scan complete banner shows
        let viewProjectsBtn = app.buttons["scan_view_projects"]
        if viewProjectsBtn.waitForExistence(timeout: 5) {
            viewProjectsBtn.tap()
            sleep(2)
        }

        // 4. Verify project list or empty state
        let hasProjects = app.staticTexts["utilio"].waitForExistence(timeout: 5)
            || app.staticTexts["No projects"].waitForExistence(timeout: 2)
        XCTAssertTrue(hasProjects || elementExists("projects_view"), "Project list did not appear")

        // 5. Settings - click through each page
        navigateTo("nav_settings")
        XCTAssertTrue(elementExists("settings_view") || elementExists("settings_sidebar"))
        for page in ["general", "services", "runtimes", "network", "cells", "deploy", "ai", "theme", "about"] {
            let item = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@", "settings_page_\(page)")
            ).firstMatch
            if item.waitForExistence(timeout: 3) { item.tap(); sleep(1) }
        }

        // 6. Deploy - switch all tabs
        navigateTo("nav_deploy")
        XCTAssertTrue(elementExists("deploy_view"))
        for tab in ["deploy_tab_terraform", "deploy_tab_ansible", "deploy_tab_containerfile", "deploy_tab_deployLog"] {
            let btn = app.buttons[tab]
            if btn.waitForExistence(timeout: 3) { btn.tap(); sleep(1) }
        }

        // 7. Tunnel - create a tunnel
        navigateTo("nav_tunnel")
        XCTAssertTrue(elementExists("tunnel_view"))
        let portField = app.textFields["tunnel_port_input"]
        if portField.waitForExistence(timeout: 5) {
            portField.tap()
            portField.typeText("9090")
            app.buttons["tunnel_create_button"].tap()
            sleep(2)
        }

        // 8. Return to Dashboard
        navigateTo("nav_dashboard")
        XCTAssertTrue(elementExists("dashboard_view"))
    }

    // MARK: - Deploy Start Flow

    func testDeployStartFlow() {
        navigateTo("nav_deploy")
        XCTAssertTrue(elementExists("deploy_view"))
        let logTab = app.buttons["deploy_tab_deployLog"]
        if logTab.waitForExistence(timeout: 3) {
            logTab.tap()
            sleep(1)
            let startBtn = app.buttons["deploy_start_button"]
            if startBtn.waitForExistence(timeout: 3) { startBtn.tap(); sleep(3) }
        }
    }

    // MARK: - AI Chat

    func testAIChatSendFlow() {
        navigateTo("nav_ai_chat")
        XCTAssertTrue(elementExists("ai_chat_view"))
        // Verify input area exists via text field query
        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 10), "AI chat input area not found")
    }
}
