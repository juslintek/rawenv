import Foundation
import Testing

@testable import RawenvLib

private struct FakeIntrospector: ServerIntrospecting {
    let caps: ServerCapabilities
    func introspect(_ target: DeployTarget) async throws -> ServerCapabilities { caps }
}

@Suite struct DeployWizardVMTests {
    @Test func recommendationPrefersExistingIaCToolingInOrder() {
        #expect(recommendedApproach(.init(hasTerraform: true, hasAnsible: true, hasDocker: true)) == .terraform)
        #expect(recommendedApproach(.init(hasAnsible: true, hasDocker: true)) == .ansible)
        #expect(recommendedApproach(.init(hasDocker: true)) == .dockerCompose)
        #expect(recommendedApproach(.init()) == .rawenvAgent)
    }

    @Test func ciProviderPipelinePaths() {
        #expect(CIProvider.github.pipelinePath == ".github/workflows/deploy.yml")
        #expect(CIProvider.gitlab.pipelinePath == ".gitlab-ci.yml")
        #expect(CIProvider.bitbucket.pipelinePath == "bitbucket-pipelines.yml")
    }

    @Test @MainActor func addRemoveAndSelectTargets() {
        let store = UserDefaultsDeployTargetStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let vm = DeployWizardVM(store: store)
        let t = DeployTarget(name: "prod", host: "1.2.3.4", user: "deploy")
        vm.addTarget(t)
        #expect(vm.targets.count == 1)
        #expect(vm.selectedTargetID == t.id)  // first add auto-selects
        vm.addTarget(t)  // dedup
        #expect(vm.targets.count == 1)
        vm.removeTarget(t)
        #expect(vm.targets.isEmpty)
        #expect(vm.selectedTargetID == nil)
    }

    @Test func targetStorePersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let store = UserDefaultsDeployTargetStore(defaults: defaults)
        store.save([DeployTarget(name: "prod", host: "h", user: "u")])
        let reloaded = UserDefaultsDeployTargetStore(defaults: defaults).load()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.name == "prod")
    }

    @Test @MainActor func introspectionDrivesRecommendation() async {
        let store = UserDefaultsDeployTargetStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let vm = DeployWizardVM(store: store, introspector: FakeIntrospector(caps: .init(hasTerraform: true)))
        vm.addTarget(DeployTarget(name: "prod", host: "h", user: "u"))
        await vm.introspectSelected()
        #expect(vm.capabilities?.hasTerraform == true)
        #expect(vm.recommendation == .terraform)
        #expect(vm.error == nil)
    }

    @Test @MainActor func planSummaryReflectsChoices() {
        let store = UserDefaultsDeployTargetStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let vm = DeployWizardVM(store: store)
        vm.addTarget(DeployTarget(name: "prod", host: "h", user: "u"))
        vm.trigger = .onPush
        vm.mode = .ciPipeline(.github)
        let summary = vm.planSummary
        #expect(summary.contains("prod"))
        #expect(summary.contains("on every push"))
        #expect(summary.contains("GitHub Actions"))
    }
}
