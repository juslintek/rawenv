import Foundation

/// Pure input validation helpers for numeric settings fields. Kept free of
/// SwiftUI so the rules can be unit-tested directly and reused by any view.
public enum SettingsValidator {
    /// A TCP port must be an integer in the inclusive range 1...65535.
    public static func isValidPort(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed) else { return false }
        return (1...65535).contains(value)
    }

    /// A memory limit is a positive number with an optional binary unit suffix
    /// (KB/MB/GB/TB, case-insensitive). A bare number is also accepted.
    public static func isValidMemoryLimit(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let pattern = "^[0-9]+(\\.[0-9]+)?\\s*(KB|MB|GB|TB|K|M|G|T)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }

    /// A CPU limit is a positive number (cores), optionally fractional.
    public static func isValidCPULimit(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed) else { return false }
        return value > 0
    }
}

/// Describes a single credential input shown for a deploy provider.
public struct CredentialField: Identifiable, Equatable, Sendable {
    public var id: String { key }
    /// Stable identifier used as the Keychain account suffix.
    public let key: String
    /// Human-readable label shown next to the field.
    public let label: String
    /// Secret fields are masked and stored in the Keychain; non-secret fields
    /// are plain text.
    public let isSecret: Bool

    public init(key: String, label: String, isSecret: Bool) {
        self.key = key
        self.label = label
        self.isSecret = isSecret
    }
}

/// Maps a deploy provider to the credential fields it requires. Drives the
/// "provider picker swaps credential fields" behaviour in Settings → Deploy.
public enum DeployProviders {
    public static let all = ["Hetzner", "DigitalOcean", "AWS", "GCP", "Azure"]

    public static func credentialFields(for provider: String) -> [CredentialField] {
        switch provider {
        case "AWS":
            return [
                CredentialField(key: "accessKeyId", label: "Access Key ID", isSecret: false),
                CredentialField(key: "secretAccessKey", label: "Secret Access Key", isSecret: true),
                CredentialField(key: "region", label: "Default Region", isSecret: false),
            ]
        case "GCP":
            return [
                CredentialField(key: "projectId", label: "Project ID", isSecret: false),
                CredentialField(key: "serviceAccountJSON", label: "Service Account JSON", isSecret: true),
            ]
        case "Azure":
            return [
                CredentialField(key: "subscriptionId", label: "Subscription ID", isSecret: false),
                CredentialField(key: "tenantId", label: "Tenant ID", isSecret: false),
                CredentialField(key: "clientId", label: "Client ID", isSecret: false),
                CredentialField(key: "clientSecret", label: "Client Secret", isSecret: true),
            ]
        case "DigitalOcean":
            return [
                CredentialField(key: "apiToken", label: "API Token", isSecret: true)
            ]
        case "Hetzner":
            return [
                CredentialField(key: "apiToken", label: "API Token", isSecret: true)
            ]
        default:
            return [
                CredentialField(key: "apiToken", label: "API Token", isSecret: true)
            ]
        }
    }
}
