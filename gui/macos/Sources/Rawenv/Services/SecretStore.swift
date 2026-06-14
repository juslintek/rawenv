import Foundation
import Security

/// Abstraction over secure secret storage (API keys, deploy credentials).
/// Lets the view model be exercised in tests with an in-memory double while
/// the app uses the macOS Keychain in production.
public protocol SecretStoring: Sendable {
    /// Stores `value` for `account`. An empty value removes the entry.
    func setSecret(_ value: String, for account: String) throws
    /// Returns the stored secret for `account`, or `nil` when absent.
    func secret(for account: String) -> String?
    /// Removes the secret for `account`. No-op when absent.
    func deleteSecret(for account: String) throws
}

/// Stores secrets as generic-password items in the macOS Keychain.
///
/// Reads never prompt and degrade gracefully (returning `nil`) when the
/// process lacks Keychain access — which is the case for the SwiftPM test
/// runner — so callers can fall back to defaults without error handling.
public final class KeychainSecretStore: SecretStoring, @unchecked Sendable {
    private let service: String

    public init(service: String = "io.rawenv.gui") {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func setSecret(_ value: String, for account: String) throws {
        // Remove any prior entry first so we can cleanly add the new value.
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = baseQuery(account)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func secret(for account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func deleteSecret(for account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    public enum KeychainError: Error { case unhandled(OSStatus) }
}

/// Well-known Keychain account names used across the app.
public enum SecretAccount {
    public static let aiAPIKey = "ai.apiKey"
    /// Account name for a deploy provider credential field, e.g.
    /// `deploy.aws.secretAccessKey`.
    public static func deploy(_ provider: String, _ field: String) -> String {
        "deploy.\(provider.lowercased()).\(field)"
    }
}
