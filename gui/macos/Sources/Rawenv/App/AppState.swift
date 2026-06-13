import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject, NavigationService {
    @Published public var currentDestination: Destination = .dashboard
    @Published public var isInstalled: Bool
    @Published public var hasCompletedSetup: Bool
    @Published public var activeProject: Project?
    @Published public var managedProjects: [Project] = []

    public let repository: DataRepository
    public let aiProvider: AIProvider
    public let serviceManager: ServiceManager
    public let aiEngine: AIEngine
    public let installerEngine: InstallerEngine
    public let scannerEngine: ScannerEngine
    public let deployEngine: DeployEngine
    public let themeManager = ThemeManager()

    // Real implementations (used when useTestDoubles = false)
    public let realServiceManager: RealServiceManager?
    public let realScannerEngine: RealScannerEngine?
    public let realInstallerEngine: RealInstallerEngine?
    public let realDeployEngine: RealDeployEngine?

    public static var useTestDoubles: Bool = {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ||
        ProcessInfo.processInfo.environment["RAWENV_TEST_MODE"] == "1"
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
