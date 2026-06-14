import Foundation

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let path: String
    public let stack: [String]
    public let deps: String
}
