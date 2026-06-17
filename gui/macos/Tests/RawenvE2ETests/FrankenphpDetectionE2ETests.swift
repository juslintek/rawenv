import Foundation
import Testing

@testable import RawenvLib

/// E2E: a project whose real stack lives in a NESTED subdirectory — a
/// `Dockerfile.franken` (FROM dunglas/frankenphp:php8.5) referenced by a
/// `docker-compose.yml` build, exactly like the gratis suite (gratis ->
/// gratis-suite). Setting it up must resolve that nested stack root and detect
/// **FrankenPHP** (php 8.5), superseding the composer-detected plain php. Fails
/// loudly if it doesn't, with the runtimes + resolved path in the message so the
/// cause is obvious.
@Suite(.serialized) struct FrankenphpDetectionE2ETests {
    private let cli = RawenvCLI(binaryPath: resolvedRawenvBinary())
    private let root = "/tmp/rawenv-frankenphp-e2e"

    @Test @MainActor func nestedFrankenphpDockerfileIsDetected() async throws {
        let fm = FileManager.default
        try? fm.removeItem(atPath: root)
        // Unique basenames so `rawenv init`'s isolated data-dir keying (basename of
        // the stack dir) can't collide with another E2E suite under parallelism.
        let project = "\(root)/frankenphp-nested-app"
        let suite = "\(project)/frankenphp-e2e-suite"  // nested stack dir, like gratis-suite
        try fm.createDirectory(atPath: suite, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: root) }

        // Parent root: a WordPress-ish composer.json, and NO compose here — the
        // stack is defined one level down.
        try #"{"name":"acme/site","require-dev":{"wp-coding-standards/wpcs":"^3.1"}}"#
            .write(toFile: "\(project)/composer.json", atomically: true, encoding: .utf8)

        // Nested suite: a compose that builds the app from Dockerfile.franken.
        try """
        services:
          wordpress:
            build:
              context: .
              dockerfile: Dockerfile.franken
            image: acme-franken:local
        volumes:
          wp_db:
        """.write(toFile: "\(suite)/docker-compose.yml", atomically: true, encoding: .utf8)
        // The Dockerfile: FrankenPHP serving PHP 8.5, SQLite embedded.
        try """
        FROM dunglas/frankenphp:php8.5-alpine
        RUN install-php-extensions pdo_sqlite sqlite3
        COPY . /app/public
        """.write(toFile: "\(suite)/Dockerfile.franken", atomically: true, encoding: .utf8)

        // Discovery would hand us the PARENT directory as the project.
        let proj = Project(name: "frankenphp-nested-app", path: project, stack: ["PHP"], deps: "")

        // Real setup: resolve the nested stack root + run `rawenv detect` there.
        let setup = ProjectSetupVM(cli: cli)
        await setup.detect(project: proj)

        let runtimeNames = setup.runtimes.map(\.name)
        #expect(
            runtimeNames.contains("frankenphp"),
            "FrankenPHP must be detected from the nested Dockerfile.franken — got runtimes \(runtimeNames), resolved stack path: \(setup.projectPath)"
        )
        // FrankenPHP embeds PHP, so it must supersede the composer-detected plain php.
        #expect(
            !runtimeNames.contains("php"),
            "frankenphp should supersede the composer-detected php (no duplicate) — got \(runtimeNames)"
        )
        if let fp = setup.runtimes.first(where: { $0.name == "frankenphp" }) {
            #expect(fp.version == "8.5", "FrankenPHP PHP line should be 8.5 from the image tag, got \(fp.version)")
        }
        // The stack root must be the nested suite dir, not the parent.
        #expect(
            setup.projectPath.hasSuffix("frankenphp-e2e-suite"),
            "detection should target the nested stack dir, got \(setup.projectPath)"
        )
    }
}
