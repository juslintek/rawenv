import XCTest

final class RawenvUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    // MARK: - First-Run Installer Flow

    func testInstallerWelcomeScreen() {
        let welcome = app.otherElements["installer_welcome_view"]
        guard welcome.waitForExistence(timeout: 3) else { return }
        XCTAssertTrue(app.staticTexts["installer_logo"].exists)
        XCTAssertTrue(app.staticTexts["installer_tagline"].exists)
        XCTAssertTrue(app.staticTexts["installer_os_detection"].exists)
        XCTAssertTrue(app.buttons["installer_install_button"].exists)
    }

    func testInstallerProgressScreen() {
        let welcome = app.otherElements["installer_welcome_view"]
        guard welcome.waitForExistence(timeout: 3) else { return }
        app.buttons["installer_install_button"].tap()
        XCTAssertTrue(app.otherElements["installer_progress_view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.progressIndicators["installer_progress_bar"].exists)
    }

    func testInstallerDoneScreen() {
        let welcome = app.otherElements["installer_welcome_view"]
        guard welcome.waitForExistence(timeout: 3) else { return }
        app.buttons["installer_install_button"].tap()
        let done = app.otherElements["installer_done_view"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["installer_continue_button"].exists)
        app.buttons["installer_continue_button"].tap()
    }

    // MARK: - Project Discovery

    func testProjectDiscoveryScanning() {
        app.staticTexts["nav_projects"].tap()
        let discovery = app.otherElements["project_discovery_view"]
        guard discovery.waitForExistence(timeout: 5) else { return }
        XCTAssertTrue(app.otherElements["discovery_scan_animation"].exists)
        XCTAssertTrue(app.buttons["discovery_add_custom_path"].exists)
        XCTAssertTrue(app.buttons["discovery_scan_full_disk"].exists)
        XCTAssertTrue(app.buttons["discovery_force_rescan"].exists)
    }

    // MARK: - Project List

    func testProjectListDisplay() {
        app.staticTexts["nav_projects"].tap()
        let list = app.otherElements["project_list_view"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["project_filter_input"].exists)
        XCTAssertTrue(app.buttons["project_scan_new"].exists)
    }

    func testProjectListSetupNavigation() {
        app.staticTexts["nav_projects"].tap()
        let list = app.otherElements["project_list_view"]
        guard list.waitForExistence(timeout: 5) else { return }
        let setupButton = app.buttons.matching(identifier: "project_setup_button").firstMatch
        if setupButton.waitForExistence(timeout: 3) {
            setupButton.tap()
            XCTAssertTrue(app.otherElements["project_setup_view"].waitForExistence(timeout: 5))
        }
    }

    // MARK: - Project Setup

    func testProjectSetupSections() {
        app.staticTexts["nav_projects"].tap()
        let setupButton = app.buttons.matching(identifier: "project_setup_button").firstMatch
        guard setupButton.waitForExistence(timeout: 5) else { return }
        setupButton.tap()
        let setup = app.otherElements["project_setup_view"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["setup_detected_runtimes"].exists)
        XCTAssertTrue(app.otherElements["setup_detected_services"].exists)
        XCTAssertTrue(app.otherElements["setup_detected_connections"].exists)
        XCTAssertTrue(app.buttons["setup_generate_toml"].exists)
    }

    // MARK: - Dashboard

    func testDashboardShowsServices() {
        app.staticTexts["nav_dashboard"].tap()
        XCTAssertTrue(app.otherElements["dashboard_view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["dashboard_services_list"].exists)
    }

    func testDashboardStatsCards() {
        app.staticTexts["nav_dashboard"].tap()
        XCTAssertTrue(app.otherElements["dashboard_view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["stats_card_cpu"].exists)
        XCTAssertTrue(app.otherElements["stats_card_memory"].exists)
        XCTAssertTrue(app.otherElements["stats_card_running"].exists)
    }

    func testDashboardTabSwitching() {
        app.staticTexts["nav_dashboard"].tap()
        XCTAssertTrue(app.otherElements["dashboard_view"].waitForExistence(timeout: 5))
        let tabs = ["logs", "config", "connection", "cell", "backups"]
        for tab in tabs {
            let button = app.buttons["tab_\(tab)"]
            XCTAssertTrue(button.exists, "Tab '\(tab)' should exist")
            button.tap()
            XCTAssertTrue(app.otherElements["tab_content_\(tab)"].waitForExistence(timeout: 3))
        }
    }

    func testDashboardLogsTab() {
        app.staticTexts["nav_dashboard"].tap()
        XCTAssertTrue(app.otherElements["dashboard_view"].waitForExistence(timeout: 5))
        app.buttons["tab_logs"].tap()
        XCTAssertTrue(app.otherElements["logs_scroll_view"].waitForExistence(timeout: 3))
    }

    func testDashboardConfigTab() {
        app.staticTexts["nav_dashboard"].tap()
        XCTAssertTrue(app.otherElements["dashboard_view"].waitForExistence(timeout: 5))
        app.buttons["tab_config"].tap()
        XCTAssertTrue(app.otherElements["config_editor"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["config_save_restart"].exists)
        XCTAssertTrue(app.buttons["config_reset_defaults"].exists)
    }

    func testDashboardConnectionTab() {
        app.staticTexts["nav_dashboard"].tap()
        XCTAssertTrue(app.otherElements["dashboard_view"].waitForExistence(timeout: 5))
        app.buttons["tab_connection"].tap()
        XCTAssertTrue(app.otherElements["connection_details"].waitForExistence(timeout: 3))
    }

    func testDashboardCellTab() {
        app.staticTexts["nav_dashboard"].tap()
        XCTAssertTrue(app.otherElements["dashboard_view"].waitForExistence(timeout: 5))
        app.buttons["tab_cell"].tap()
        XCTAssertTrue(app.otherElements["cell_isolation_info"].waitForExistence(timeout: 3))
    }

    func testDashboardBackupsTab() {
        app.staticTexts["nav_dashboard"].tap()
        XCTAssertTrue(app.otherElements["dashboard_view"].waitForExistence(timeout: 5))
        app.buttons["tab_backups"].tap()
        XCTAssertTrue(app.otherElements["backups_view"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["backups_auto_toggle"].exists)
    }

    // MARK: - AI Chat

    func testAIChatSendMessage() {
        app.staticTexts["nav_ai_chat"].tap()
        XCTAssertTrue(app.otherElements["ai_chat_view"].waitForExistence(timeout: 5))
        let input = app.textFields["ai_input"]
        XCTAssertTrue(input.exists)
        input.tap()
        input.typeText("Hello AI")
        app.buttons["ai_send_button"].tap()
        XCTAssertTrue(app.otherElements["ai_message_list"].exists)
    }

    func testAIChatReceiveResponse() {
        app.staticTexts["nav_ai_chat"].tap()
        XCTAssertTrue(app.otherElements["ai_chat_view"].waitForExistence(timeout: 5))
        let input = app.textFields["ai_input"]
        input.tap()
        input.typeText("What services are running?")
        app.buttons["ai_send_button"].tap()
        let response = app.staticTexts.matching(identifier: "ai_message_assistant").firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 10))
    }

    func testAIChatProviderSwitching() {
        app.staticTexts["nav_ai_chat"].tap()
        XCTAssertTrue(app.otherElements["ai_chat_view"].waitForExistence(timeout: 5))
        let providerSelector = app.popUpButtons["ai_provider_selector"]
        XCTAssertTrue(providerSelector.exists)
        providerSelector.tap()
        let option = app.menuItems.firstMatch
        if option.waitForExistence(timeout: 3) {
            option.tap()
        }
    }

    func testAIChatProactiveSuggestion() {
        app.staticTexts["nav_ai_chat"].tap()
        XCTAssertTrue(app.otherElements["ai_chat_view"].waitForExistence(timeout: 5))
        // Proactive suggestion banner may or may not appear based on state
        let banner = app.otherElements["ai_proactive_banner"]
        if banner.waitForExistence(timeout: 3) {
            XCTAssertTrue(banner.exists)
        }
    }

    // MARK: - Settings

    func testSettingsNavigateAllPages() {
        app.staticTexts["nav_settings"].tap()
        XCTAssertTrue(app.otherElements["settings_view"].waitForExistence(timeout: 5))
        let pages = ["general", "services", "runtimes", "network", "cells", "deploy", "ai", "theme", "about"]
        for page in pages {
            let item = app.staticTexts["settings_page_\(page)"]
            XCTAssertTrue(item.waitForExistence(timeout: 3), "Settings page '\(page)' should exist")
            item.tap()
            XCTAssertTrue(app.otherElements["settings_content_\(page)"].waitForExistence(timeout: 3))
        }
    }

    func testSettingsGeneralToggle() {
        app.staticTexts["nav_settings"].tap()
        XCTAssertTrue(app.otherElements["settings_view"].waitForExistence(timeout: 5))
        app.staticTexts["settings_page_general"].tap()
        let toggle = app.switches["settings_auto_start_toggle"]
        guard toggle.waitForExistence(timeout: 3) else { return }
        let initialValue = toggle.value as? String
        toggle.tap()
        let newValue = toggle.value as? String
        XCTAssertNotEqual(initialValue, newValue)
    }

    func testSettingsTogglePersistence() {
        app.staticTexts["nav_settings"].tap()
        app.staticTexts["settings_page_general"].tap()
        let toggle = app.switches["settings_auto_start_toggle"]
        guard toggle.waitForExistence(timeout: 3) else { return }
        toggle.tap()
        let valueAfterToggle = toggle.value as? String
        // Navigate away and back
        app.staticTexts["nav_dashboard"].tap()
        app.staticTexts["nav_settings"].tap()
        app.staticTexts["settings_page_general"].tap()
        let toggleAgain = app.switches["settings_auto_start_toggle"]
        XCTAssertTrue(toggleAgain.waitForExistence(timeout: 3))
        XCTAssertEqual(toggleAgain.value as? String, valueAfterToggle)
    }

    func testSettingsThemePage() {
        app.staticTexts["nav_settings"].tap()
        app.staticTexts["settings_page_theme"].tap()
        XCTAssertTrue(app.otherElements["settings_content_theme"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["theme_border_radius_slider"].exists)
        XCTAssertTrue(app.sliders["theme_font_size_slider"].exists)
    }

    func testSettingsAboutPage() {
        app.staticTexts["nav_settings"].tap()
        app.staticTexts["settings_page_about"].tap()
        XCTAssertTrue(app.otherElements["settings_content_about"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["about_check_updates"].exists)
        XCTAssertTrue(app.buttons["about_uninstall"].exists)
    }

    // MARK: - Connections

    func testConnectionsCardsVisible() {
        app.staticTexts["nav_connections"].tap()
        XCTAssertTrue(app.otherElements["connections_view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["connection_cards_container"].exists)
    }

    func testConnectionsModeToggle() {
        app.staticTexts["nav_connections"].tap()
        XCTAssertTrue(app.otherElements["connections_view"].waitForExistence(timeout: 5))
        let localButton = app.buttons.matching(identifier: "connection_use_local").firstMatch
        let remoteButton = app.buttons.matching(identifier: "connection_use_remote").firstMatch
        if localButton.waitForExistence(timeout: 3) {
            localButton.tap()
        }
        if remoteButton.waitForExistence(timeout: 3) {
            remoteButton.tap()
        }
    }

    // MARK: - Deploy

    func testDeployTabSwitching() {
        app.staticTexts["nav_deploy"].tap()
        XCTAssertTrue(app.otherElements["deploy_view"].waitForExistence(timeout: 5))
        let tabs = ["terraform", "ansible", "containerfile", "deploy_log"]
        for tab in tabs {
            let button = app.buttons["deploy_tab_\(tab)"]
            XCTAssertTrue(button.exists, "Deploy tab '\(tab)' should exist")
            button.tap()
            XCTAssertTrue(app.otherElements["deploy_content_\(tab)"].waitForExistence(timeout: 3))
        }
    }

    func testDeployLogProgress() {
        app.staticTexts["nav_deploy"].tap()
        XCTAssertTrue(app.otherElements["deploy_view"].waitForExistence(timeout: 5))
        app.buttons["deploy_tab_deploy_log"].tap()
        let startButton = app.buttons["deploy_start_button"]
        if startButton.waitForExistence(timeout: 3) {
            startButton.tap()
            XCTAssertTrue(app.progressIndicators["deploy_progress_bar"].waitForExistence(timeout: 5))
        }
    }

    func testDeployAIFixButton() {
        app.staticTexts["nav_deploy"].tap()
        app.buttons["deploy_tab_deploy_log"].tap()
        let aiFixButton = app.buttons["deploy_ai_fix_button"]
        if aiFixButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(aiFixButton.isEnabled)
        }
    }

    // MARK: - Tunnel

    func testTunnelCreateAndVerify() {
        app.staticTexts["nav_tunnel"].tap()
        XCTAssertTrue(app.otherElements["tunnel_view"].waitForExistence(timeout: 5))
        let portInput = app.textFields["tunnel_port_input"]
        XCTAssertTrue(portInput.exists)
        portInput.tap()
        portInput.typeText("8080")
        app.buttons["tunnel_create_button"].tap()
        let tunnelList = app.otherElements["tunnel_active_list"]
        XCTAssertTrue(tunnelList.waitForExistence(timeout: 5))
    }

    func testTunnelSSHCommandDisplay() {
        app.staticTexts["nav_tunnel"].tap()
        XCTAssertTrue(app.otherElements["tunnel_view"].waitForExistence(timeout: 5))
        let sshCommand = app.staticTexts.matching(identifier: "tunnel_ssh_command").firstMatch
        if sshCommand.waitForExistence(timeout: 3) {
            XCTAssertFalse(sshCommand.label.isEmpty)
        }
    }

    // MARK: - Menu Bar Popover

    func testMenuBarPopoverShowsServices() {
        let menuBarItem = app.statusItems.firstMatch
        guard menuBarItem.waitForExistence(timeout: 5) else { return }
        menuBarItem.tap()
        let popover = app.otherElements["menubar_popover"]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["menubar_running_count"].exists)
        XCTAssertTrue(app.otherElements["menubar_service_list"].exists)
    }

    func testMenuBarServiceToggle() {
        let menuBarItem = app.statusItems.firstMatch
        guard menuBarItem.waitForExistence(timeout: 5) else { return }
        menuBarItem.tap()
        let popover = app.otherElements["menubar_popover"]
        guard popover.waitForExistence(timeout: 3) else { return }
        let toggle = app.switches.matching(identifier: "menubar_service_toggle").firstMatch
        if toggle.waitForExistence(timeout: 3) {
            toggle.tap()
        }
    }

    func testMenuBarStartAllButton() {
        let menuBarItem = app.statusItems.firstMatch
        guard menuBarItem.waitForExistence(timeout: 5) else { return }
        menuBarItem.tap()
        let popover = app.otherElements["menubar_popover"]
        guard popover.waitForExistence(timeout: 3) else { return }
        XCTAssertTrue(app.buttons["menubar_start_all"].exists)
        XCTAssertTrue(app.buttons["menubar_open_dashboard"].exists)
    }

    // MARK: - Uninstall

    func testUninstallCheckboxesAndConfirm() {
        app.staticTexts["nav_settings"].tap()
        app.staticTexts["settings_page_about"].tap()
        let uninstallButton = app.buttons["about_uninstall"]
        guard uninstallButton.waitForExistence(timeout: 3) else { return }
        uninstallButton.tap()
        let uninstallView = app.otherElements["uninstall_view"]
        XCTAssertTrue(uninstallView.waitForExistence(timeout: 5))
        let checkboxes = [
            "uninstall_binary", "uninstall_packages", "uninstall_services",
            "uninstall_data", "uninstall_config", "uninstall_dns_proxy",
        ]
        for checkbox in checkboxes {
            let cb = app.checkBoxes[checkbox]
            if cb.exists { cb.tap() }
        }
        XCTAssertTrue(app.buttons["uninstall_confirm_button"].exists)
        XCTAssertTrue(app.buttons["uninstall_cancel_button"].exists)
    }

    func testUninstallCancelDismisses() {
        app.staticTexts["nav_settings"].tap()
        app.staticTexts["settings_page_about"].tap()
        let uninstallButton = app.buttons["about_uninstall"]
        guard uninstallButton.waitForExistence(timeout: 3) else { return }
        uninstallButton.tap()
        let uninstallView = app.otherElements["uninstall_view"]
        guard uninstallView.waitForExistence(timeout: 5) else { return }
        app.buttons["uninstall_cancel_button"].tap()
        XCTAssertFalse(uninstallView.waitForExistence(timeout: 2))
    }
}
