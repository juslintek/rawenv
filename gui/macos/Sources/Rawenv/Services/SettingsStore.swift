import Foundation

/// Abstraction over persisting ``AppSettings`` so the view model can be tested
/// against a temporary file (or an in-memory double) without touching the
/// user's real configuration.
public protocol SettingsPersisting: Sendable {
    /// Returns the persisted settings, or `nil` when no valid file exists yet.
    func load() -> AppSettings?
    /// Writes the settings to durable storage, creating parent dirs as needed.
    func save(_ settings: AppSettings) throws
    /// The on-disk location settings are written to (for diagnostics/tests).
    var location: URL { get }
}

/// Persists ``AppSettings`` as pretty-printed JSON at
/// `~/.rawenv/settings.json` by default. Secrets (API keys) are never written
/// here — those live in the Keychain via ``SecretStoring``.
public final class SettingsStore: SettingsPersisting, @unchecked Sendable {
    public let location: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.location = fileURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.location = home
                .appendingPathComponent(".rawenv", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
        }
    }

    public func load() -> AppSettings? {
        guard let data = try? Data(contentsOf: location) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let dir = location.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: location, options: .atomic)
    }
}
