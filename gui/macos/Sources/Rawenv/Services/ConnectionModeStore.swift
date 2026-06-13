import Foundation

/// Persists the user's per-connection mode choice (local / remote / proxy) so
/// the selection survives navigating away from the Connections screen — and a
/// full app restart. Abstracted behind a protocol so unit tests can use an
/// in-memory double instead of the shared `UserDefaults`.
public protocol ConnectionModePersisting: Sendable {
    /// The persisted mode for an env var, or `nil` when the user never chose one.
    func mode(for envVar: String) -> String?
    /// Persist the chosen mode for an env var.
    func setMode(_ mode: String, for envVar: String)
}

/// `UserDefaults`-backed implementation. Keys are namespaced under
/// `rawenv.connectionMode.<envVar>` so they never collide with other settings.
public final class ConnectionModeStore: ConnectionModePersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix = "rawenv.connectionMode."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func mode(for envVar: String) -> String? {
        defaults.string(forKey: prefix + envVar)
    }

    public func setMode(_ mode: String, for envVar: String) {
        defaults.set(mode, forKey: prefix + envVar)
    }
}
