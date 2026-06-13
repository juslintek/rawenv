import Testing
import Foundation
@testable import RawenvLib

@Suite struct ProjectSetupVMTests {
    @Test func updatedTomlReplacesExistingNodeLine() {
        let toml = """
        [project]
        name = "app"

        [runtimes]
        node = "18"

        [services]
        postgresql = "16"
        """
        let out = ProjectSetupVM.updatedToml(toml, nodeVersion: "22")
        #expect(out.contains("node = \"22\""))
        #expect(!out.contains("node = \"18\""))
        // Other sections preserved
        #expect(out.contains("[services]"))
        #expect(out.contains("postgresql = \"16\""))
    }

    @Test func updatedTomlInsertsNodeWhenMissingInRuntimes() {
        let toml = """
        [project]
        name = "app"

        [runtimes]
        php = "8.3"
        """
        let out = ProjectSetupVM.updatedToml(toml, nodeVersion: "20")
        #expect(out.contains("node = \"20\""))
        #expect(out.contains("php = \"8.3\""))
    }

    @Test func updatedTomlAppendsRuntimesSectionWhenAbsent() {
        let toml = """
        [project]
        name = "app"
        """
        let out = ProjectSetupVM.updatedToml(toml, nodeVersion: "22")
        #expect(out.contains("[runtimes]"))
        #expect(out.contains("node = \"22\""))
    }

    @Test @MainActor func nodeVersionChoicesIncludesDetected() {
        let vm = ProjectSetupVM()
        vm.nodeVersion = "21"
        #expect(vm.nodeVersionChoices.contains("21"))
        #expect(vm.nodeVersionChoices.first == "21")
    }

    @Test @MainActor func setNodeVersionWritesToConfig() throws {
        let dir = NSTemporaryDirectory() + "rawenv-node-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let tomlPath = "\(dir)/rawenv.toml"
        try "[project]\nname = \"app\"\n\n[runtimes]\nnode = \"18\"\n".write(toFile: tomlPath, atomically: true, encoding: .utf8)

        let vm = ProjectSetupVM()
        vm.projectPath = dir
        vm.projectName = "app"
        vm.runtimes = [.init(name: "node", version: "18")]
        vm.setNodeVersion("22")

        #expect(vm.nodeVersion == "22")
        let written = try String(contentsOfFile: tomlPath, encoding: .utf8)
        #expect(written.contains("node = \"22\""))
        #expect(vm.runtimes.first?.version == "22")
    }
}
