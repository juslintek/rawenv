import Foundation

public struct AIMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(role)-\(text.prefix(20))" }
    public let role: String
    public let text: String
}
