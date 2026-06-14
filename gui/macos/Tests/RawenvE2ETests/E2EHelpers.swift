import Foundation

@testable import RawenvLib

// Shared path resolution for E2E tests. Resolves the rawenv CLI and repo fixture
// from candidate paths, validating executability before committing to one, so a
// missing binary surfaces as a clear "rawenv not found on PATH" rather than an
// opaque Process error. CI sets RAWENV_BINARY / RAWENV_REPO; local dev falls
// back to a repo-relative build, then a conventional checkout path.

/// First executable rawenv CLI among the candidates, else a bare "rawenv" for a
/// PATH lookup.
func resolvedRawenvBinary() -> String {
    let candidates = [
        ProcessInfo.processInfo.environment["RAWENV_BINARY"],
        "\(FileManager.default.currentDirectoryPath)/../../zig-out/bin/rawenv",
        "/Volumes/Projects/rawenv/zig-out/bin/rawenv",
    ].compactMap { $0 }
    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
    }
    return "rawenv"
}

/// The rawenv repo root used as a fixture by some E2E tests.
func resolvedRawenvRepo() -> String {
    if let repo = ProcessInfo.processInfo.environment["RAWENV_REPO"], !repo.isEmpty {
        return repo
    }
    let relative = "\(FileManager.default.currentDirectoryPath)/../.."
    if FileManager.default.fileExists(atPath: "\(relative)/rawenv.toml") {
        return relative
    }
    return "/Volumes/Projects/rawenv"
}
