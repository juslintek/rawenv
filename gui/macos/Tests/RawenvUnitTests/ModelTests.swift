import Testing
@testable import RawenvLib

@Suite struct ModelTests {
    @Test func aiMessageId() {
        let msg = AIMessage(role: "user", text: "Hello world test message")
        #expect(msg.id == "user-Hello world test mes")
        #expect(msg.role == "user")
        #expect(msg.text == "Hello world test message")
    }

    @Test func connectionId() {
        let conn = Connection(envVar: "DATABASE_URL", original: "postgres://host", local: "postgres://localhost", mode: "local", badge: "Local", proxy: nil, alternative: nil)
        #expect(conn.id == "DATABASE_URL")
    }

    @Test func connectionWithProxy() {
        let conn = Connection(envVar: "REDIS_URL", original: "redis://remote", local: "redis://localhost", mode: "proxy", badge: "Proxied", proxy: "localhost:6379 → remote:6379", alternative: "alt")
        #expect(conn.proxy == "localhost:6379 → remote:6379")
        #expect(conn.alternative == "alt")
    }

    @Test func logEntryId() {
        let log = LogEntry(time: "14:23:01", msg: "ready", level: "info")
        #expect(log.id == "14:23:01-ready")
    }

    @Test func projectId() {
        let p = Project(name: "myapp", path: "~/Projects/myapp", stack: ["Node.js", "Redis"], deps: "5 deps")
        #expect(p.id == "myapp")
        #expect(p.stack.count == 2)
    }

    @Test func serviceId() {
        let s = Service(name: "PostgreSQL", port: 5432, version: "16.2", pid: 1234, cpu: "2.1%", mem: "84MB", uptime: "3h", status: "running", icon: "🐘")
        #expect(s.id == "PostgreSQL")
        #expect(s.pid == 1234)
        #expect(s.cpu == "2.1%")
        #expect(s.mem == "84MB")
        #expect(s.uptime == "3h")
    }

    @Test func serviceHashable() {
        let s1 = Service(name: "Redis", port: 6379, version: "7.4", pid: nil, cpu: nil, mem: nil, uptime: nil, status: "stopped", icon: "🔴")
        let s2 = Service(name: "Redis", port: 6379, version: "7.4", pid: nil, cpu: nil, mem: nil, uptime: nil, status: "stopped", icon: "🔴")
        #expect(s1 == s2)
        #expect(s1.hashValue == s2.hashValue)
    }

    @Test func appSettingsEquatable() {
        let s1 = GeneralSettings(storeLocation: "~/.rawenv", autoStartServices: true, autoDetectProjects: true, launchAtLogin: false, fileWatcher: false, scanPaths: ["~/Projects"])
        let s2 = GeneralSettings(storeLocation: "~/.rawenv", autoStartServices: true, autoDetectProjects: true, launchAtLogin: false, fileWatcher: false, scanPaths: ["~/Projects"])
        #expect(s1 == s2)
    }

    @Test func networkSettings() {
        let n = NetworkSettings(localDomain: ".test", autoTls: true, proxyPort: 443, tunnelProvider: "bore", relayServer: "bore.pub")
        #expect(n.localDomain == ".test")
        #expect(n.autoTls == true)
    }

    @Test func cellsSettings() {
        let c = CellsSettings(enableByDefault: true, defaultMemoryLimit: "256MB", defaultCpuLimit: "2", networkIsolation: true)
        #expect(c.enableByDefault == true)
        #expect(c.networkIsolation == true)
    }

    @Test func deploySettings() {
        let d = DeploySettings(provider: "Hetzner", sshKey: "~/.ssh/id_ed25519", terraformPath: "/usr/local/bin/terraform", ansiblePath: "/usr/local/bin/ansible", autoGenerate: true, containerRuntime: "podman", registry: "ghcr.io")
        #expect(d.provider == "Hetzner")
        #expect(d.autoGenerate == true)
    }

    @Test func aiSettings() {
        let a = AISettings(provider: "groq", providers: ["groq", "cerebras"], apiKey: "", ollamaEndpoint: "http://localhost:11434", proactiveSuggestions: true, autoApplySafeFixes: false, includeLogsInContext: true, maxContextSize: 8192, autonomyLevels: ["suggest-only"], defaultAutonomy: "suggest-only")
        #expect(a.providers.count == 2)
        #expect(a.maxContextSize == 8192)
    }

    @Test func themeSettings() {
        let t = ThemeSettings(mode: "dark", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171", warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)
        #expect(t.mode == "dark")
        #expect(t.borderRadius == 8)
    }

    @Test func deployConfig() {
        let d = DeployConfig(terraform: "resource {}", ansible: "- hosts: all", containerfile: "FROM node:22")
        #expect(d.terraform == "resource {}")
    }

    @Test func installerConfig() {
        let pi = PlatformInfo(icon: "🍎", name: "macOS", detail: "Apple Silicon", serviceManager: "launchd", isolation: "Seatbelt", dns: "dnsmasq")
        let ic = InstallerConfig(steps: ["download", "extract", "configure"], platforms: ["macos": pi])
        #expect(ic.steps.count == 3)
        #expect(ic.platforms["macos"]?.serviceManager == "launchd")
    }

    @Test func destinationCases() {
        let all = Destination.allCases
        #expect(all.contains(.dashboard))
        #expect(all.contains(.settings))
        #expect(all.contains(.aiChat))
        #expect(all.contains(.connections))
        #expect(all.contains(.deploy))
        #expect(all.contains(.tunnel))
        #expect(all.contains(.menuBar))
        #expect(all.contains(.installer))
        #expect(all.contains(.projects))
        #expect(all.contains(.uninstall))
    }

    @Test func aiAutonomyLevelCases() {
        let all = AIAutonomyLevel.allCases
        #expect(all.count == 4)
        #expect(AIAutonomyLevel.suggestOnly.rawValue == "suggest-only")
        #expect(AIAutonomyLevel.autoApplySafe.rawValue == "auto-apply-safe")
        #expect(AIAutonomyLevel.confirmDangerous.rawValue == "confirm-dangerous")
        #expect(AIAutonomyLevel.fullAutonomous.rawValue == "full-autonomous")
    }

    @Test func settingsPageCases() {
        let all = SettingsPage.allCases
        #expect(all.count == 9)
    }

    @Test func deployTabCases() {
        let all = DeployViewTab.allCases
        #expect(all.count == 4)
        #expect(DeployViewTab.terraform.rawValue == "terraform")
    }

    @Test func arraySubscriptSafe() {
        let arr = [1, 2, 3]
        #expect(arr[safe: 0] == 1)
        #expect(arr[safe: 5] == nil)
    }
}
