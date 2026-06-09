import Foundation

public struct Connection: Codable, Identifiable, Equatable {
    public var id: String { envVar }
    public let envVar: String
    public let original: String
    public let local: String?
    public let mode: String
    public let badge: String
    public let proxy: String?
    public let alternative: String?
}
