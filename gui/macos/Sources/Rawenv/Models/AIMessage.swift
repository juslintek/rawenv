import Foundation

public struct AIMessage: Codable, Identifiable, Equatable {
    public var id: String { "\(role)-\(text.prefix(20))" }
    public let role: String
    public let text: String
}
