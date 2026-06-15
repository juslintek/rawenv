import Foundation
import Testing

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
        try "[project]\nname = \"app\"\n\n[runtimes]\nnode = \"18\"\n".write(
            toFile: tomlPath, atomically: true, encoding: .utf8)

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

extension ProjectSetupVMTests {
    @Test func resolveStackRootFindsNestedComposeDir() throws {
        // A project whose compose lives in a subdir (e.g. gratis -> gratis-suite)
        // resolves to that subdir so the full stack is detected.
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rawenv-stack-\(UUID().uuidString)")
        let suite = root.appendingPathComponent("app-suite")
        try fm.createDirectory(at: suite, withIntermediateDirectories: true)
        try Data("services: {}\n".utf8).write(to: suite.appendingPathComponent("docker-compose.yml"))
        defer { try? fm.removeItem(at: root) }

        #expect(ProjectSetupVM.resolveStackRoot(root.path) == suite.path)
    }

    @Test func resolveStackRootPrefersRootWhenItHasCompose() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rawenv-stack-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("services: {}\n".utf8).write(to: root.appendingPathComponent("docker-compose.yml"))
        defer { try? fm.removeItem(at: root) }

        #expect(ProjectSetupVM.resolveStackRoot(root.path) == root.path)
    }

    @Test func resolveStackRootReturnsPathWhenNoComposeAnywhere() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rawenv-stack-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        #expect(ProjectSetupVM.resolveStackRoot(root.path) == root.path)
    }
}
