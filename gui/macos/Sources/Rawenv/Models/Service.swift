import Foundation

public struct Service: Codable, Identifiable, Equatable, Hashable {
    public var id: String { name }
    public let name: String
    public let port: Int
    public let version: String
    public let pid: Int?
    public let cpu: String?
    public let mem: String?
    public let uptime: String?
    public let status: String
    public let icon: String
}
