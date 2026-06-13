import Testing
import Foundation
@testable import RawenvLib

@Suite struct MenuBarActionsTests {
    @Test func terminalScriptRunsTuiWithBinaryPath() {
        let actions = MenuBarActions(binaryPath: "/usr/local/bin/rawenv")
        let script = actions.terminalAppleScript()
        #expect(script.contains("/usr/local/bin/rawenv tui"))
        #expect(script.contains("Terminal"))
        #expect(script.contains("do script"))
    }

    @Test func openTUIArgumentsUseOsascriptScript() {
        let actions = MenuBarActions(binaryPath: "/opt/rawenv")
        let args = actions.openTUIArguments()
        #expect(args.first == "-e")
        #expect(args.count == 2)
        #expect(args[1].contains("/opt/rawenv tui"))
    }

    @Test func statusStateNoneWhenNothingRunning() {
        #expect(MenuBarActions.statusState(running: 0, total: 5) == .none)
        #expect(MenuBarActions.statusState(running: 0, total: 0) == .none)
    }

    @Test func statusStatePartialWhenSomeRunning() {
        #expect(MenuBarActions.statusState(running: 2, total: 5) == .partial)
    }

    @Test func statusStateAllRunningWhenEveryServiceRunning() {
        #expect(MenuBarActions.statusState(running: 5, total: 5) == .allRunning)
    }
}

@Suite struct RawenvServiceBackendTests {
    @Test func backendIsTheDefaultManagerBackend() async {
        // The CLI-backed backend should satisfy the ServiceBackend protocol and
        // be usable as ServiceManager's production default without a launchd
        // dependency. We only assert it constructs and conforms here; behaviour
        // against a live CLI is covered by RealServiceManagerTests.
        let backend: ServiceBackend = RawenvServiceBackend(cli: RawenvCLI(binaryPath: "/nonexistent/rawenv"))
        // list() throws when the binary is missing; start/stop are no-ops.
        await backend.start("PostgreSQL")
        await backend.stop("PostgreSQL")
        await #expect(throws: (any Error).self) {
            _ = try await backend.list()
        }
    }
}
