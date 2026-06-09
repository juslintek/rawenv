import Foundation

// Type aliases for backward compatibility.
// AppState references these Real* names — these aliases resolve them
// to the actual implementation classes.

public typealias RealServiceManager = ServiceManager
public typealias RealScannerEngine = ScannerEngine
public typealias RealInstallerEngine = InstallerEngine
public typealias RealDeployEngine = DeployEngine
public typealias RealDataRepository = DataStore
public typealias RealAIProvider = AIProviderCascade
