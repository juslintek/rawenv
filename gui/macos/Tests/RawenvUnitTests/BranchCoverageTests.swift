import Testing
import SwiftUI
import AppKit
@testable import RawenvLib

@MainActor
private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 1200, height: 900)) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layout()
    // Force display to trigger deeper evaluation
    hostingView.display()
}

@MainActor
private func makeState() -> AppState {
    UserDefaults.standard.set(true, forKey: "rawenv.installed")
    UserDefaults.standard.set(true, forKey: "rawenv.setupComplete")
    let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
    state.activeProject = Project(name: "utilio", path: "~/Projects/utilio", stack: ["Node.js", "Redis", "PostgreSQL", "Meilisearch"], deps: "14 deps")
    state.managedProjects = [state.activeProject!]
    return state
}

// MARK: - DeployView branches

@Suite struct DeployViewBranchTests {
    @Test @MainActor func terraformTab() async {
        let tm = ThemeManager()
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        render(DeployView(viewModel: vm, initialTab: .terraform).environmentObject(tm))
    }

    @Test @MainActor func ansibleTab() async {
        let tm = ThemeManager()
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        render(DeployView(viewModel: vm, initialTab: .ansible).environmentObject(tm))
    }

    @Test @MainActor func containerfileTab() async {
        let tm = ThemeManager()
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        render(DeployView(viewModel: vm, initialTab: .containerfile).environmentObject(tm))
    }

    @Test @MainActor func deployLogTab() async {
        let tm = ThemeManager()
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        render(DeployView(viewModel: vm, initialTab: .deployLog).environmentObject(tm))
    }

    @Test @MainActor func deployLogWithProgress() async {
        let tm = ThemeManager()
        let engine = DeployEngine()
        let vm = DeployViewModel(repository: TestDataRepository(), deployEngine: engine)
        await vm.load()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        render(DeployView(viewModel: vm, initialTab: .deployLog).environmentObject(tm))
    }

    @Test @MainActor func deployLogWithError() async {
        let tm = ThemeManager()
        let engine = DeployEngine()
        let vm = DeployViewModel(repository: TestDataRepository(), deployEngine: engine)
        await vm.load()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        render(DeployView(viewModel: vm, initialTab: .deployLog).environmentObject(tm))
    }

    @Test @MainActor func deployLogAfterFix() async {
        let tm = ThemeManager()
        let engine = DeployEngine()
        let vm = DeployViewModel(repository: TestDataRepository(), deployEngine: engine)
        await vm.load()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        engine.applyAIFix()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        render(DeployView(viewModel: vm, initialTab: .deployLog).environmentObject(tm))
    }
}

// MARK: - ProjectsView all pages

@Suite struct ProjectsViewBranchTests {
    @Test @MainActor func discoveryPage() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        engine.paths = [
            .init(path: "~/Done/", status: .done, projectCount: 3, cached: true),
            .init(path: "~/Scanning/", status: .scanning, projectCount: 0, cached: false),
            .init(path: "~/Queued/", status: .queued, projectCount: 0, cached: false),
        ]
        engine.scanComplete = false
        engine.isScanning = true
        await vm.load()
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .discovery).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func discoveryComplete() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        engine.scanComplete = true
        engine.isScanning = false
        engine.newProjectsFound = 5
        await vm.load()
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .discovery).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func listPage() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        await vm.load()
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .list).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func setupPage() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        await vm.load()
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .setup).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func discoveryNotComplete() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        engine.scanComplete = false
        engine.isScanning = false
        await vm.load()
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .discovery).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func installSheetInProgress() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        let installVM = InstallFlowVM()
        await vm.load()
        installVM.startInstall(name: "Node.js", action: "install")
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .setup, installVM: installVM).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func installSheetError() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        let installVM = InstallFlowVM()
        await vm.load()
        installVM.startInstall(name: "SQL Server", action: "install")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .setup, installVM: installVM).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func installSheetPortError() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        let installVM = InstallFlowVM()
        await vm.load()
        installVM.startInstall(name: "SQL Server", action: "install")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        installVM.requestPortChange()
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .setup, installVM: installVM).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func installSheetComplete() async {
        let state = makeState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        let installVM = InstallFlowVM()
        await vm.load()
        installVM.startInstall(name: "Node.js", action: "install")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        render(ProjectsView(viewModel: vm, engine: engine, initialPage: .setup, installVM: installVM).environmentObject(state).environmentObject(tm))
    }
}

// MARK: - ContentView all destinations

@Suite struct ContentViewBranchTests {
    @Test @MainActor func allDestinations() async {
        let state = makeState()
        let tm = ThemeManager()
        try? await Task.sleep(nanoseconds: 300_000_000)

        for dest in Destination.allCases {
            state.currentDestination = dest
            render(ContentView().environmentObject(state).environmentObject(tm))
        }
    }

    @Test @MainActor func noActiveProject() async {
        let state = makeState()
        state.activeProject = nil
        state.managedProjects = []
        let tm = ThemeManager()
        try? await Task.sleep(nanoseconds: 300_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func multipleProjects() async {
        let state = makeState()
        let p2 = Project(name: "blog", path: "~/blog", stack: ["Ruby"], deps: "3 deps")
        state.managedProjects.append(p2)
        let tm = ThemeManager()
        try? await Task.sleep(nanoseconds: 300_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }
}

// MARK: - DashboardView all tabs

@Suite struct DashboardViewBranchTests {
    @Test @MainActor func allTabs() async {
        let tm = ThemeManager()
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()

        for tab in DashboardTab.allCases {
            vm.selectedTab = tab
            render(DashboardView(viewModel: vm).environmentObject(tm))
        }
    }

    @Test @MainActor func selectedService() async {
        let tm = ThemeManager()
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        // Select different services
        if let second = vm.services.dropFirst().first {
            vm.selectedService = second
            render(DashboardView(viewModel: vm).environmentObject(tm))
        }
    }

    @Test @MainActor func logColors() async {
        let tm = ThemeManager()
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        vm.selectedTab = .logs
        render(DashboardView(viewModel: vm).environmentObject(tm))
    }
}

// MARK: - AIChatView branches

@Suite struct AIChatViewBranchTests {
    @Test @MainActor func withMessages() async {
        let tm = ThemeManager()
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: TestAIProvider())
        await vm.load()
        render(AIChatView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func withLoading() async {
        let tm = ThemeManager()
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: TestAIProvider())
        await vm.load()
        // Trigger loading state
        vm.inputText = "test"
        // Start send but don't await
        Task { await vm.sendMessage() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        render(AIChatView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func emptyMessages() {
        let tm = ThemeManager()
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: TestAIProvider())
        render(AIChatView(viewModel: vm).environmentObject(tm))
    }
}

// MARK: - ConnectionsView branches

@Suite struct ConnectionsViewBranchTests {
    @Test @MainActor func allModes() async {
        let tm = ThemeManager()
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        // Set different modes
        for conn in vm.connections {
            vm.connectionModes[conn.envVar] = "local"
        }
        render(ConnectionsView(viewModel: vm).environmentObject(tm))

        for conn in vm.connections {
            vm.connectionModes[conn.envVar] = "remote"
        }
        render(ConnectionsView(viewModel: vm).environmentObject(tm))

        for conn in vm.connections {
            vm.connectionModes[conn.envVar] = "proxy"
        }
        render(ConnectionsView(viewModel: vm).environmentObject(tm))
    }
}

// MARK: - MenuBarView branches

@Suite struct MenuBarViewBranchTests {
    @Test @MainActor func withServices() async {
        let state = makeState()
        let tm = ThemeManager()
        try? await Task.sleep(nanoseconds: 300_000_000)
        render(MenuBarView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func withStoppedServices() async {
        let state = makeState()
        let tm = ThemeManager()
        try? await Task.sleep(nanoseconds: 300_000_000)
        state.serviceManager.stopAll()
        render(MenuBarView().environmentObject(state).environmentObject(tm))
    }
}

// MARK: - ServiceManager additional coverage

@Suite struct ServiceManagerCoverageTests {
    @Test @MainActor func restartServiceFlow() async {
        let mgr = ServiceManager(repository: TestDataRepository())
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let name = mgr.services.first?.name else { return }
        mgr.restartService(name: name)
        // After delay, it should be running
        try? await Task.sleep(nanoseconds: 800_000_000)
        let svc = mgr.services.first(where: { $0.name == name })
        #expect(svc?.status == "running")
    }
}

// MARK: - DataStore fallback paths

