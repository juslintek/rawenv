import Foundation
import Testing

@testable import RawenvLib

/// End-to-end: rawenv allocates non-conflicting ports for two instances of the
/// SAME service, then we start real Redis on each, verify they run independently
/// with isolated data, and clean up.
@Suite(.serialized) struct MultiInstanceE2ETests {

    private let cli = RawenvCLI(
        binaryPath: resolvedRawenvBinary())
    private let root = "/tmp/rawenv-multi-instance"
    private let redisBin = "/opt/homebrew/bin/redis-server"

    struct ServiceJSON: Decodable {
        let name: String
        let port: Int
        let status: String
    }

    @Test func twoRedisInstancesOnDistinctAllocatedPorts() async throws {
        guard FileManager.default.isExecutableFile(atPath: redisBin) else {
            print("SKIP: redis-server not installed")
            return
        }

        // Setup: project with two redis instances, no explicit ports → rawenv auto-allocates.
        try? FileManager.default.removeItem(atPath: root)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try """
        name = "multi"
        version = "1"

        [services.redis.cache]
        version = "7"

        [services.redis.queue]
        version = "7"
        """.write(toFile: "\(root)/rawenv.toml", atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(atPath: root) }

        // Ask rawenv for the resolved ports.
        let services = try await cli.runJSON(["services", "ls", "--json"], as: [ServiceJSON].self, cwd: root)
        #expect(services.count == 2)
        let cache = services.first { $0.name == "redis.cache" }!
        let queue = services.first { $0.name == "redis.queue" }!

        // Core assertion: rawenv gave the two same-service instances DIFFERENT ports.
        #expect(cache.port != queue.port, "instances must not share a port")
        #expect(cache.port != 0 && queue.port != 0)

        // Start a real redis on each allocated port, with isolated data dirs.
        for svc in [cache, queue] {
            let dir = "\(root)/data/\(svc.name)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            _ = shell(
                "redis-server --port \(svc.port) --daemonize yes --dir '\(dir)' --save '' --appendonly no --loglevel warning"
            )
        }
        defer {
            for svc in [cache, queue] { _ = shell("redis-cli -p \(svc.port) shutdown nosave") }
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Both respond independently on their own ports.
        #expect(shell("redis-cli -p \(cache.port) ping").contains("PONG"))
        #expect(shell("redis-cli -p \(queue.port) ping").contains("PONG"))

        // Write DISTINCT data to each and verify isolation.
        _ = shell("redis-cli -p \(cache.port) SET instance cache-data")
        _ = shell("redis-cli -p \(queue.port) SET instance queue-data")
        #expect(shell("redis-cli -p \(cache.port) GET instance").contains("cache-data"))
        #expect(shell("redis-cli -p \(queue.port) GET instance").contains("queue-data"))
        // The key in cache must NOT leak into queue and vice versa.
        #expect(!shell("redis-cli -p \(cache.port) GET instance").contains("queue-data"))

        // Stop both and verify ports are freed.
        for svc in [cache, queue] { _ = shell("redis-cli -p \(svc.port) shutdown nosave") }
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(!isPortOpen(cache.port))
        #expect(!isPortOpen(queue.port))
    }

    @Test func explicitPortOverrideIsHonoredEndToEnd() async throws {
        guard FileManager.default.isExecutableFile(atPath: redisBin) else {
            print("SKIP: redis-server not installed")
            return
        }
        let dir = "\(root)-override"
        try? FileManager.default.removeItem(atPath: dir)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try """
        name = "ovr"
        version = "1"

        [services.redis.main]
        version = "7"
        port = 16399
        """.write(toFile: "\(dir)/rawenv.toml", atomically: true, encoding: .utf8)

        let services = try await cli.runJSON(["services", "ls", "--json"], as: [ServiceJSON].self, cwd: dir)
        #expect(services.first?.port == 16399)

        _ = shell(
            "redis-server --port 16399 --daemonize yes --dir '\(dir)' --save '' --appendonly no --loglevel warning")
        defer { _ = shell("redis-cli -p 16399 shutdown nosave") }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(shell("redis-cli -p 16399 ping").contains("PONG"))
    }

    // MARK: - Helpers

    private func shell(_ cmd: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func isPortOpen(_ port: Int) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "lsof -i :\(port) -sTCP:LISTEN 2>/dev/null | grep -q LISTEN"]
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
