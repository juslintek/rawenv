import Foundation

public enum Destination: String, CaseIterable {
    case dashboard, settings, aiChat, connections, deploy, tunnel
    case menuBar, installer, projects, uninstall
}

@MainActor
public protocol NavigationService: AnyObject {
    var currentDestination: Destination { get set }
    func navigate(to destination: Destination)
}
