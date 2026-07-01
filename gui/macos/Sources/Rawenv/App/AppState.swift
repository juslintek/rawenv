import Combine
import Foundation

@MainActor
public final class AppState: ObservableObject, NavigationService {
    @Published public var currentDestination: Destination = .dashboard
    @Published public var isInstalled: Bool
    @Published public var hasCompletedSetup: Bool
    @Published public var activeProject: Project? {
        didSet {
            guard let path = activeProject?.path else { return }
            // Point the data layer at the active project's directory so
            // project-scoped CLI reads (services/connections/config) resolve
            // against the right rawenv.toml instead of the app's launch dir ("/").
            repository.useProject(path: ProjectSetupVM.resolveStackRoot(path))
            // Reload the dashboard so it reflects the now-active project. The
            // dashboard is the landing view and often loads on launch BEFORE the
            // project (and its directory) are known — without this it stays stuck
            // on the stale "isn't set up yet" empty state even for a configured
            // project.
            Task { await dashboardVM.load() }
        }
    }
    @Published public var managedProjects: [Project] = []

    public let repository: DataRepository
    public let aiProvider: AIProvider
    public let serviceManager: ServiceManager
    public let aiEngine: AIEngine
    public let installerEngine: InstallerEngine
    public let scannerEngine: ScannerEngine
    public let deployEngine: DeployEngine
    public let themeManager = ThemeManager()

    // Cached ViewModels — created once, never recreated on navigation.
    // This prevents the process-storm bug where each body evaluation spawned new CLI processes.
    public lazy var dashboardVM: DashboardViewModel = DashboardViewModel(repository: repository)
    public lazy var aiChatVM: AIChatViewModel = AIChatViewModel(repository: repository, aiProvider: aiProvider)
    public lazy var connectionsVM: ConnectionsViewModel = ConnectionsViewModel(repository: repository)
    public lazy var deployVM: DeployViewModel = DeployViewModel(
        repository: repository, projectPath: activeProject?.path, deployEngine: deployEngine)
    public lazy var tunnelVM: TunnelVM = TunnelVM(
        commandRunner: { TunnelVM.runRawenvTunnel(port: $0) }, repository: repository)
    public lazy var projectsVM: ProjectsViewModel = ProjectsViewModel(repository: repository)

    // Real implementations (used when useTestDoubles = false)
    public let realServiceManager: RealServiceManager?
    public let realScannerEngine: RealScannerEngine?
    public let realInstallerEngine: RealInstallerEngine?
    public let realDeployEngine: RealDeployEngine?

    public static var useTestDoubles: Bool = {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
            || ProcessInfo.processInfo.environment["RAWENV_TEST_MODE"] == "1"
    }()

    public init(repository: DataRepository, aiProvider: AIProvider) {
        self.repository = repository
        self.aiProvider = aiProvider
        self.serviceManager = ServiceManager(repository: repository)
        self.aiEngine = AIEngine()
        self.installerEngine = InstallerEngine()
        self.scannerEngine = ScannerEngine()
        self.deployEngine = DeployEngine()

        if Self.useTestDoubles {
            realServiceManager = nil
            realScannerEngine = nil
            realInstallerEngine = nil
            realDeployEngine = nil
        } else {
            realServiceManager = RealServiceManager()
            realScannerEngine = RealScannerEngine()
            realInstallerEngine = RealInstallerEngine()
            realDeployEngine = RealDeployEngine()
        }

        let defaults = UserDefaults.standard
        if Self.useTestDoubles {
            self.isInstalled = true
            self.hasCompletedSetup = true
        } else {
            self.isInstalled = defaults.bool(forKey: "rawenv.installed")
            self.hasCompletedSetup = defaults.bool(forKey: "rawenv.setupComplete")
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let projects = (try? await repository.fetchProjects()) ?? []
            if let first = projects.first {
                self.managedProjects = [first]
                self.activeProject = first
            }
        }
    }

    /// Convenience factory for real mode
    public static func real() -> AppState {
        let cli = RawenvCLI()
        let repo = RealDataRepository(cli: cli)
        let ai = RealAIProvider()
        Self.useTestDoubles = false
        return AppState(repository: repo, aiProvider: ai)
    }

    /// Convenience factory for test mode
    public static func testing() -> AppState {
        Self.useTestDoubles = true
        return AppState(repository: DataStore(), aiProvider: AIProviderCascade())
    }

    public func addManagedProject(_ project: Project) {
        if !managedProjects.contains(where: { $0.id == project.id }) {
            managedProjects.append(project)
        }
        activeProject = project
    }

    public func navigate(to destination: Destination) {
        currentDestination = destination
    }

    public func markInstalled() {
        isInstalled = true
        UserDefaults.standard.set(true, forKey: "rawenv.installed")
    }

    public func markSetupComplete() {
        hasCompletedSetup = true
        UserDefaults.standard.set(true, forKey: "rawenv.setupComplete")
    }

    public func resetFirstRun() {
        isInstalled = false
        hasCompletedSetup = false
        UserDefaults.standard.removeObject(forKey: "rawenv.installed")
        UserDefaults.standard.removeObject(forKey: "rawenv.setupComplete")
    }
}
