import Foundation
import Combine
import AppKit

@MainActor
public final class ConnectionsViewModel: ObservableObject {
    @Published public var connections: [Connection] = []
    @Published public var connectionModes: [String: String] = [:]

    private let repository: DataRepository
    private let modeStore: ConnectionModePersisting

    public init(repository: DataRepository,
                modeStore: ConnectionModePersisting = ConnectionModeStore()) {
        self.repository = repository
        self.modeStore = modeStore
    }

    public func load() async {
        connections = await repository.fetchConnections()
        for conn in connections {
            // Prefer the user's persisted choice so the selected mode survives
            // navigating away and back (and app restarts); fall back to the
            // mode reported by the data layer on first use.
            connectionModes[conn.envVar] = modeStore.mode(for: conn.envVar) ?? conn.mode
        }
    }

    public func setMode(_ mode: String, for envVar: String) {
        connectionModes[envVar] = mode
        modeStore.setMode(mode, for: envVar)
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
