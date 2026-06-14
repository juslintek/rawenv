import Foundation

public struct LogEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(time)-\(msg)" }
    public let time: String
    public let msg: String
    public let level: String
}
