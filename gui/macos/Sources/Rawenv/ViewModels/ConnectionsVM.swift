import Foundation
import Combine
import AppKit

@MainActor
public final class ConnectionsViewModel: ObservableObject {
    @Published public var connections: [Connection] = []
    @Published public var connectionModes: [String: String] = [:]

    private let repository: DataRepository

    public init(repository: DataRepository) {
        self.repository = repository
    }

    public func load() async {
        connections = await repository.fetchConnections()
        for conn in connections {
            connectionModes[conn.envVar] = conn.mode
        }
    }

    public func setMode(_ mode: String, for envVar: String) {
        connectionModes[envVar] = mode
    }

    public func connectionString(for connection: Connection) -> String {
        let mode = connectionModes[connection.envVar] ?? connection.mode
        switch mode {
        case "local": return connection.local ?? connection.original
        case "proxy": return connection.proxy ?? connection.original
        default: return connection.original
        }
    }

    public func copyConnectionString(for connection: Connection) {
        let str = connectionString(for: connection)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
    }
}
