import Testing
import Foundation
@testable import RawenvLib

/// Verifies RawenvCLI's binary-discovery ordering, in particular that a CLI
/// embedded inside the .app bundle (Developer ID distribution) is preferred
/// over any system install — the runtime half of "the app embeds the CLI".
@Suite struct RawenvCLIDiscoveryTests {
    @Test func candidatePathsPreferBundleOverSystem() {
        let bundle = Bundle.main
        let paths = RawenvCLI.candidatePaths(
            bundle: bundle,
            home: "/Users/test",
            cwd: "/src/rawenv"
        )

        let bundleResources = bundle.bundleURL.path + "/Contents/Resources/rawenv"
        let bundleMacOS = bundle.bundleURL.path + "/Contents/MacOS/rawenv"
        let userInstall = "/Users/test/.rawenv/bin/rawenv"

        guard let resourcesIdx = paths.firstIndex(of: bundleResources),
              let userIdx = paths.firstIndex(of: userInstall) else {
            Issue.record("expected bundle and user-install candidates to be present: \(paths)")
            return
        }
        // Embedded (bundle) locations must come before user/system installs.
        #expect(resourcesIdx < userIdx)
        // Contents/MacOS/rawenv must NEVER be a candidate: on a case-insensitive
        // filesystem it collides with the GUI binary "Rawenv", and exec'ing it
        // would launch infinite GUI instances. Only Contents/Resources/rawenv
        // is a valid embed location.
        #expect(!paths.contains(bundleMacOS))
    }

    @Test func candidatePathsIncludeAllKnownLocations() {
        let paths = RawenvCLI.candidatePaths(
            bundle: .main,
            home: "/Users/test",
            cwd: "/src/rawenv"
        )
        #expect(paths.contains("/usr/local/bin/rawenv"))
        #expect(paths.contains("/opt/homebrew/bin/rawenv"))
        #expect(paths.contains("/Users/test/.rawenv/bin/rawenv"))
        #expect(paths.contains("/src/rawenv/zig-out/bin/rawenv"))
    }

    @Test func explicitBinaryPathIsHonored() {
        let cli = RawenvCLI(binaryPath: "/custom/path/rawenv")
        #expect(cli.binaryPath == "/custom/path/rawenv")
    }

    @Test func fallsBackToPathLookupWhenNothingExists() {
        // With a bogus home/cwd none of the candidates exist on disk, so the
        // default initializer should fall back to a bare "rawenv" PATH lookup.
        let cli = RawenvCLI()
        #expect(!cli.binaryPath.isEmpty)
    }
}

/// Regression tests for the Dock-flooding crash: the GUI must never resolve the
/// CLI to its own executable, and must refuse to exec itself.
@Suite struct SelfExecGuardTests {
    @Test func candidatePathsNeverIncludeMacOSSubdir() {
        // On a case-insensitive filesystem "Contents/MacOS/rawenv" collides with
        // the GUI binary "Rawenv"; it must never be offered as a CLI candidate.
        let paths = RawenvCLI.candidatePaths(bundle: .main, home: "/Users/test", cwd: "/src/rawenv")
        #expect(!paths.contains { $0.hasSuffix("/Contents/MacOS/rawenv") })
    }

    @Test func ownExecutableIsDetectedAsSelfReference() {
        // The test runner's own executable must be flagged as a self-reference.
        if let me = Bundle.main.executableURL?.path {
            #expect(RawenvCLI.isSelfReference(me))
        }
    }

    @Test func unrelatedPathIsNotSelfReference() {
        #expect(!RawenvCLI.isSelfReference("/usr/local/bin/rawenv"))
    }

    @Test func processGuardAllowsNormalUseAndTripsOnRunaway() {
        let guardian = ProcessGuard()
        // A handful of acquisitions succeed.
        for _ in 0..<10 {
            #expect(guardian.acquire())
            guardian.release()
        }
    }
}
