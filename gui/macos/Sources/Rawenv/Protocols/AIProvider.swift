import Foundation

public enum AIAutonomyLevel: String, CaseIterable, Codable, Sendable {
    case suggestOnly = "suggest-only"
    case autoApplySafe = "auto-apply-safe"
    case confirmDangerous = "confirm-dangerous"
    case fullAutonomous = "full-autonomous"
}

public protocol AIProvider: Sendable {
    func send(prompt: String) async -> String
    var autonomyLevel: AIAutonomyLevel { get set }
}
