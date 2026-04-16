import SwiftUI
import AppKit

// MARK: - Theme
extension Color {
    static let bgPrimary = Color(red: 0x0f/255, green: 0x0f/255, blue: 0x14/255)
    static let bgSecondary = Color(red: 0x16/255, green: 0x16/255, blue: 0x1e/255)
    static let bgTertiary = Color(red: 0x1e/255, green: 0x1e/255, blue: 0x2a/255)
    static let bgHover = Color(red: 0x25/255, green: 0x25/255, blue: 0x35/255)
    static let accent2 = Color(red: 0x63/255, green: 0x66/255, blue: 0xf1/255)
    static let accentHover = Color(red: 0x81/255, green: 0x8c/255, blue: 0xf8/255)
    static let success2 = Color(red: 0x34/255, green: 0xd3/255, blue: 0x99/255)
    static let warning2 = Color(red: 0xfb/255, green: 0xbf/255, blue: 0x24/255)
    static let error2 = Color(red: 0xf8/255, green: 0x71/255, blue: 0x71/255)
    static let info2 = Color(red: 0x60/255, green: 0xa5/255, blue: 0xfa/255)
    static let textPrimary = Color(red: 0xe2/255, green: 0xe4/255, blue: 0xf0/255)
    static let textMuted2 = Color(red: 0x8b/255, green: 0x8d/255, blue: 0xa6/255)
    static let textDisabled = Color(red: 0x4a/255, green: 0x4b/255, blue: 0x5e/255)
    static let border2 = Color(red: 0x2a/255, green: 0x2a/255, blue: 0x3a/255)
}

// MARK: - Model
enum ServiceStatus { case running, stopped }
enum DashboardTab: String, CaseIterable { case logs = "Logs", config = "Config", connection = "Connection", cell = "Cell", backups = "Backups" }
enum SettingsTab: String, CaseIterable { case general = "General", services = "Services", network = "Network", theme = "Theme", about = "About" }

struct Service: Identifiable {
    let id = UUID()
    let name: String; let version: String; let port: Int; let status: ServiceStatus
    let pid: String; let cpu: String; let mem: String; let uptime: String
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time: String; let level: String; let msg: String
}

class AppModel: ObservableObject {
    @Published var selectedService: Int = 0
    @Published var activeTab: DashboardTab = .logs
    @Published var services: [Service] = []
    @Published var logs: [LogEntry] = []
    @Published var showSettings: Bool = false
    @Published var settingsTab: SettingsTab = .general

    init() { loadData() }

    func loadData() {
        // Try reading rawenv.toml from cwd
        let cwd = FileManager.default.currentDirectoryPath
        let tomlPath = "\(cwd)/rawenv.toml"
        if let content = try? String(contentsOfFile: tomlPath, encoding: .utf8) {
            services = parseToml(content)
        }
        if services.isEmpty { loadMockData() }
        logs = mockLogs()
    }

    private func parseToml(_ content: String) -> [Service] {
        var svcs: [Service] = []
        var inRuntimes = false, inServices = false
        for line in content.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l == "[runtimes]" { inRuntimes = true; inServices = false; continue }
            if l == "[services]" { inServices = true; inRuntimes = false; continue }
            if l.hasPrefix("[") { inRuntimes = false; inServices = false; continue }
            if (inRuntimes || inServices), let eq = l.firstIndex(of: "=") {
                let name = l[l.startIndex..<eq].trimmingCharacters(in: .whitespaces)
                let ver = l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                let port = defaultPort(name)
                let installed = isInstalled(name, ver)
                svcs.append(Service(name: name, version: ver, port: port,
                    status: installed ? .running : .stopped,
                    pid: installed ? "\(Int.random(in: 40000...50000))" : "—",
                    cpu: installed ? "\(Double.random(in: 0.1...8.0).formatted(.number.precision(.fractionLength(1))))%" : "—",
                    mem: installed ? "\(Int.random(in: 10...200))MB" : "—",
                    uptime: installed ? "2h 14m" : "—"))
            }
        }
        return svcs
    }

    private func defaultPort(_ name: String) -> Int {
        switch name {
        case "postgresql", "postgres": return 5432
        case "redis": return 6379
        case "mysql", "mariadb": return 3306
        case "node": return 3000
        case "meilisearch": return 7700
        default: return 0
        }
    }

    private func isInstalled(_ name: String, _ version: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return FileManager.default.fileExists(atPath: "\(home)/.rawenv/bin/\(name)")
    }

    private func loadMockData() {
        services = [
            Service(name: "PostgreSQL", version: "16.2", port: 5432, status: .running, pid: "48291", cpu: "2.1%", mem: "84MB", uptime: "2h 14m"),
            Service(name: "Redis", version: "7.2.4", port: 6379, status: .running, pid: "48305", cpu: "0.3%", mem: "12MB", uptime: "2h 14m"),
            Service(name: "Meilisearch", version: "1.6.0", port: 7700, status: .running, pid: "48312", cpu: "1.8%", mem: "156MB", uptime: "2h 14m"),
            Service(name: "Node.js", version: "22.15.0", port: 3000, status: .running, pid: "48320", cpu: "7.4%", mem: "210MB", uptime: "45m"),
            Service(name: "SQL Server", version: "2022", port: 1433, status: .stopped, pid: "—", cpu: "—", mem: "—", uptime: "—"),
        ]
    }

    private func mockLogs() -> [LogEntry] {[
        LogEntry(time: "14:23:01", level: "normal", msg: "LOG:  database system is ready to accept connections"),
        LogEntry(time: "14:23:05", level: "normal", msg: "LOG:  autovacuum launcher started"),
        LogEntry(time: "14:25:12", level: "active", msg: "LOG:  connection received: host=127.0.0.1 port=52341"),
        LogEntry(time: "14:25:12", level: "active", msg: "LOG:  connection authorized: user=myapp database=myapp_dev"),
        LogEntry(time: "14:30:44", level: "warn", msg: "WARNING:  could not open statistics file"),
        LogEntry(time: "14:35:01", level: "normal", msg: "LOG:  checkpoint starting: time"),
        LogEntry(time: "14:35:02", level: "normal", msg: "LOG:  checkpoint complete: wrote 42 buffers (0.3%)"),
        LogEntry(time: "14:40:15", level: "active", msg: "LOG:  connection received: host=127.0.0.1 port=52388"),
        LogEntry(time: "14:45:01", level: "normal", msg: "LOG:  checkpoint starting: time"),
        LogEntry(time: "14:55:03", level: "error", msg: "ERROR:  terminating connection due to administrator command"),
    ]}

    var currentService: Service { services.indices.contains(selectedService) ? services[selectedService] : services[0] }
    var runningCount: Int { services.filter { $0.status == .running }.count }
}

// MARK: - Sidebar
struct SidebarView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project selector
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName()).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(FileManager.default.currentDirectoryPath).font(.system(size: 10)).foregroundColor(.textMuted2).lineLimit(1)
                }
                Spacer()
                Text("▾").foregroundColor(.textMuted2)
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color.bgTertiary))
            .padding(.horizontal, 12).padding(.top, 12)

            // Services section
            Text("SERVICES").font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted2)
                .tracking(1).padding(.leading, 16).padding(.top, 16).padding(.bottom, 4)

            ForEach(Array(model.services.enumerated()), id: \.element.id) { i, svc in
                SidebarServiceRow(svc: svc, selected: i == model.selectedService)
                    .onTapGesture { model.selectedService = i }
            }

            Spacer()

            // Bottom actions
            Divider().background(Color.border2)
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill").font(.system(size: 14))
                    .foregroundColor(model.showSettings ? .accent2 : .textMuted2)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 6).fill(model.showSettings ? Color.bgTertiary : Color.clear))
                    .onTapGesture { model.showSettings.toggle() }
                Spacer()
            }.padding(.horizontal, 12).padding(.top, 8)
            HStack(spacing: 8) {
                ActionButton(label: "▶ Start All", color: .accent2)
                ActionButton(label: "⏹ Stop All", color: .bgTertiary)
            }.padding(12)
        }
        .frame(width: 240).background(Color.bgSecondary)
    }

    func projectName() -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).lastPathComponent
    }
}

struct SidebarServiceRow: View {
    let svc: Service; let selected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(svc.status == .running ? Color.success2 : Color.error2).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(svc.name).font(.system(size: 13, weight: .medium))
                    .foregroundColor(svc.status == .stopped ? .textDisabled : .textPrimary)
                HStack {
                    Text(":\(svc.port)").font(.system(size: 11, design: .monospaced)).foregroundColor(.textMuted2)
                    Spacer()
                    Text(svc.status == .running ? "running" : "stopped")
                        .font(.system(size: 10)).foregroundColor(svc.status == .running ? .success2 : .error2)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(selected ? Color.bgTertiary : Color.clear)
        .overlay(selected ? Rectangle().fill(Color.accent2).frame(width: 3) : nil, alignment: .leading)
        .cornerRadius(selected ? 0 : 0)
    }
}

struct ActionButton: View {
    let label: String; let color: Color
    var body: some View {
        Text(label).font(.system(size: 12, weight: .semibold))
            .foregroundColor(color == .accent2 ? .white : .textMuted2)
            .frame(maxWidth: .infinity, minHeight: 32).background(RoundedRectangle(cornerRadius: 6).fill(color))
    }
}

// MARK: - Main Content
struct ContentArea: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ServiceHeader(svc: model.currentService)
            StatsRow(svc: model.currentService)
            TabBar(active: $model.activeTab)
            LogViewer(logs: model.logs, serviceName: model.currentService.name)
            ConnectionBar(svc: model.currentService)
        }.background(Color.bgPrimary)
    }
}

struct ServiceHeader: View {
    let svc: Service
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(svc.name).font(.system(size: 20, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    SmallButton(label: "⏹ Stop", color: .error2)
                    SmallButton(label: "↻ Restart", color: .warning2)
                }
            }
            Text("Version \(svc.version) · Port \(svc.port) · PID \(svc.pid) · Uptime \(svc.uptime)")
                .font(.system(size: 13)).foregroundColor(.textMuted2)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(Color.bgSecondary)
        .overlay(Divider().background(Color.border2), alignment: .bottom)
    }
}

struct SmallButton: View {
    let label: String; let color: Color
    var body: some View {
        Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgTertiary))
    }
}

struct StatsRow: View {
    let svc: Service
    var body: some View {
        HStack(spacing: 16) {
            StatCard(label: "CPU", value: svc.cpu, progress: 0.02, color: .success2)
            StatCard(label: "Memory", value: svc.mem, progress: 0.25, color: .accentHover)
            StatCard(label: "Connections", value: "3", sub: "/ 100", progress: nil, color: .textPrimary)
            StatCard(label: "Disk", value: "245 MB", progress: 0.05, color: .info2)
        }.padding(.horizontal, 24).padding(.vertical, 12)
    }
}

struct StatCard: View {
    let label: String; let value: String; var sub: String? = nil; var progress: Double? = nil; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.textMuted2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(.textPrimary)
                if let s = sub { Text(s).font(.system(size: 14)).foregroundColor(.textMuted2) }
            }
            if let p = progress {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.bgTertiary).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(color).frame(width: g.size.width * p, height: 6)
                    }
                }.frame(height: 6)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSecondary))
    }
}

struct TabBar: View {
    @Binding var active: DashboardTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                VStack(spacing: 0) {
                    Text(tab.rawValue).font(.system(size: 12, weight: tab == active ? .semibold : .regular))
                        .foregroundColor(tab == active ? .textPrimary : .textMuted2)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    Rectangle().fill(tab == active ? Color.accent2 : Color.clear).frame(height: 3).cornerRadius(1.5)
                }.onTapGesture { active = tab }
            }
            Spacer()
        }
        .background(Color.bgSecondary).overlay(Divider().background(Color.border2), alignment: .bottom)
        .padding(.horizontal, 24)
    }
}

struct LogViewer: View {
    let logs: [LogEntry]; let serviceName: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(logs) { log in
                    HStack(alignment: .top, spacing: 12) {
                        Text(log.time).font(.system(size: 12, design: .monospaced)).foregroundColor(.textDisabled).frame(width: 70, alignment: .leading)
                        Text(log.msg).font(.system(size: 12, design: .monospaced)).foregroundColor(logColor(log.level)).lineLimit(nil)
                    }.padding(.vertical, 1)
                }
                // Cursor
                Rectangle().fill(Color.accent2.opacity(0.8)).frame(width: 8, height: 16).padding(.top, 4)
            }.padding(16)
        }
        .background(Color.bgPrimary).cornerRadius(8).padding(.horizontal, 24).padding(.top, 8)
        .frame(maxHeight: .infinity)
    }

    func logColor(_ level: String) -> Color {
        switch level {
        case "error": return .error2
        case "warn": return .warning2
        case "active": return .textPrimary
        default: return .textMuted2
        }
    }
}

struct ConnectionBar: View {
    let svc: Service
    var body: some View {
        HStack {
            Text("postgresql://myapp:****@localhost:\(svc.port)/myapp_dev")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.textMuted2)
            Spacer()
            Text("Copy").font(.system(size: 11, weight: .medium)).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accent2))
                .onTapGesture { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("postgresql://localhost:\(svc.port)", forType: .string) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.bgTertiary).cornerRadius(6)
        .padding(.horizontal, 24).padding(.bottom, 12)
    }
}

// MARK: - Settings
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            // Left nav
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("←").foregroundColor(.accent2)
                    Text("Back").font(.system(size: 12, weight: .medium)).foregroundColor(.accent2)
                }.padding(12).onTapGesture { model.showSettings = false }
                Divider().background(Color.border2)
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    HStack(spacing: 8) {
                        Text(settingsIcon(tab)).font(.system(size: 13))
                        Text(tab.rawValue).font(.system(size: 13, weight: .medium))
                            .foregroundColor(tab == model.settingsTab ? .textPrimary : .textMuted2)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(tab == model.settingsTab ? Color.bgTertiary : Color.clear)
                    .cornerRadius(6).padding(.horizontal, 8)
                    .onTapGesture { model.settingsTab = tab }
                }
                Spacer()
            }.frame(width: 160).background(Color.bgSecondary)
            // Right content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsContent(model.settingsTab)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color.bgPrimary)
        }
    }

    func settingsIcon(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: return "⚙"
        case .services: return "☰"
        case .network: return "🌐"
        case .theme: return "🎨"
        case .about: return "ℹ"
        }
    }

    @ViewBuilder func settingsContent(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: settingsGeneral()
        case .services: settingsServices()
        case .network: settingsNetwork()
        case .theme: settingsTheme()
        case .about: settingsAbout()
        }
    }

    func settingsGeneral() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.system(size: 20, weight: .bold)).foregroundColor(.textPrimary)
            SettingsRow(label: "Project", value: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).lastPathComponent)
            SettingsRow(label: "rawenv version", value: "0.2.0")
            SettingsRow(label: "Data directory", value: "\(FileManager.default.homeDirectoryForCurrentUser.path)/.rawenv")
            SettingsRow(label: "Config file", value: "\(FileManager.default.currentDirectoryPath)/rawenv.toml")
        }
    }

    func settingsServices() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Services").font(.system(size: 20, weight: .bold)).foregroundColor(.textPrimary)
            ForEach(model.services) { svc in
                HStack {
                    Circle().fill(svc.status == .running ? Color.success2 : Color.error2).frame(width: 8, height: 8)
                    Text(svc.name).font(.system(size: 13, weight: .medium)).foregroundColor(.textPrimary)
                    Text(svc.version).font(.system(size: 12)).foregroundColor(.textMuted2)
                    Spacer()
                    Text(svc.status == .running ? "ON" : "OFF")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(svc.status == .running ? .success2 : .textDisabled)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.bgTertiary))
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSecondary))
            }
        }
    }

    func settingsNetwork() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network").font(.system(size: 20, weight: .bold)).foregroundColor(.textPrimary)
            SettingsRow(label: "DNS masking", value: "Disabled")
            SettingsRow(label: "Proxy", value: "None")
            SettingsRow(label: "Listen address", value: "127.0.0.1")
        }
    }

    func settingsTheme() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme").font(.system(size: 20, weight: .bold)).foregroundColor(.textPrimary)
            SettingsRow(label: "Color mode", value: "Dark")
            SettingsRow(label: "Accent color", value: "#6366F1")
        }
    }

    func settingsAbout() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About").font(.system(size: 20, weight: .bold)).foregroundColor(.textPrimary)
            SettingsRow(label: "Version", value: "0.2.0")
            SettingsRow(label: "License", value: "MIT")
            Text("github.com/nicholasgasior/rawenv").font(.system(size: 12)).foregroundColor(.accent2)
        }
    }
}

struct SettingsRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(.textMuted2)
            Spacer()
            Text(value).font(.system(size: 13, design: .monospaced)).foregroundColor(.textPrimary)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSecondary))
    }
}

// MARK: - Root
struct DashboardView: View {
    @StateObject var model = AppModel()
    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
            if model.showSettings {
                SettingsView(model: model)
            } else {
                ContentArea(model: model)
            }
        }
        .frame(width: 1100, height: 720)
        .background(Color.bgPrimary)
    }
}

@main
struct RawenvGUI: App {
    var body: some Scene {
        WindowGroup { DashboardView() }
            .windowStyle(.titleBar)
            .windowResizability(.contentSize)
    }
}
