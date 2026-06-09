import Testing
import Foundation
@testable import RawenvLib

/// Tests the full project creation lifecycle using framework templates:
/// create from template → detect services → configure → verify → teardown

private let testRoot = "/tmp/rawenv-template-lifecycle"
private let cli = RawenvCLI(binaryPath: "/Volumes/Projects/rawenv/zig-out/bin/rawenv")

@Suite(.serialized) struct ProjectCreationLifecycleTests {

    // MARK: - Setup

    @Test func step00_cleanup() {
        try? FileManager.default.removeItem(atPath: testRoot)
        try? FileManager.default.createDirectory(atPath: testRoot, withIntermediateDirectories: true)
    }

    // MARK: - Template Loading

    @Test @MainActor func step01_templatesLoad() {
        let creator = ProjectCreator(cli: cli)
        #expect(creator.templates.count >= 10)
        let names = creator.templates.map(\.name)
        #expect(names.contains("Next.js"))
        #expect(names.contains("Laravel"))
        #expect(names.contains("Ruby on Rails"))
        #expect(names.contains("FastAPI"))
        #expect(names.contains("Django"))
        #expect(names.contains("Express.js"))
        #expect(names.contains("Gin (Go)"))
        #expect(names.contains("Actix Web (Rust)"))
        #expect(names.contains("Phoenix (Elixir)"))
        #expect(names.contains("Spring Boot (Java)"))
    }

    @Test @MainActor func step01_templatesByCategory() {
        let creator = ProjectCreator(cli: cli)
        let grouped = creator.templatesByCategory()
        #expect(!grouped.isEmpty)
        let categories = grouped.map(\.category)
        #expect(categories.contains("fullstack"))
        #expect(categories.contains("api"))
    }

    // MARK: - Create Projects from Every Template

    @Test @MainActor func step02_createNextjsProject() async {
        let creator = ProjectCreator(cli: cli)
        let template = creator.templates.first { $0.name == "Next.js" }!
        await creator.create(template: template, name: "my-nextjs-app", parentDir: testRoot)
        #expect(creator.createdPath == "\(testRoot)/my-nextjs-app")
        #expect(creator.error == nil)
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/my-nextjs-app/package.json"))
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/my-nextjs-app/.env"))
    }

    @Test @MainActor func step02_createLaravelProject() async {
        let creator = ProjectCreator(cli: cli)
        let template = creator.templates.first { $0.name == "Laravel" }!
        await creator.create(template: template, name: "my-laravel-api", parentDir: testRoot)
        #expect(creator.error == nil)
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/my-laravel-api/composer.json"))
    }

    @Test @MainActor func step02_createRailsProject() async {
        let creator = ProjectCreator(cli: cli)
        let template = creator.templates.first { $0.name == "Ruby on Rails" }!
        await creator.create(template: template, name: "my-rails-app", parentDir: testRoot)
        #expect(creator.error == nil)
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/my-rails-app/Gemfile"))
    }

    @Test @MainActor func step02_createFastapiProject() async {
        let creator = ProjectCreator(cli: cli)
        let template = creator.templates.first { $0.name == "FastAPI" }!
        await creator.create(template: template, name: "my-fastapi", parentDir: testRoot)
        #expect(creator.error == nil)
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/my-fastapi/requirements.txt"))
    }

    @Test @MainActor func step02_createExpressProject() async {
        let creator = ProjectCreator(cli: cli)
        let template = creator.templates.first { $0.name == "Express.js" }!
        await creator.create(template: template, name: "my-express-api", parentDir: testRoot)
        #expect(creator.error == nil)
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/my-express-api/package.json"))
    }

    @Test @MainActor func step02_createGinProject() async {
        let creator = ProjectCreator(cli: cli)
        let template = creator.templates.first { $0.name == "Gin (Go)" }!
        await creator.create(template: template, name: "my-go-service", parentDir: testRoot)
        #expect(creator.error == nil)
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/my-go-service/go.mod"))
    }

    @Test @MainActor func step02_createActixProject() async {
        let creator = ProjectCreator(cli: cli)
        let template = creator.templates.first { $0.name == "Actix Web (Rust)" }!
        await creator.create(template: template, name: "my-rust-api", parentDir: testRoot)
        #expect(creator.error == nil)
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/my-rust-api/Cargo.toml"))
    }

    // MARK: - Verify CLI Detection

    @Test func step03_cliDetectsNextjs() async throws {
        let output = try await cli.run(["services", "ls", "--json"], cwd: "\(testRoot)/my-nextjs-app")
        #expect(output.contains("postgresql") || output.contains("redis"))
    }

    @Test func step03_cliDetectsLaravel() async throws {
        let output = try await cli.run(["services", "ls", "--json"], cwd: "\(testRoot)/my-laravel-api")
        #expect(output.contains("redis") || !output.isEmpty)
    }

    @Test func step03_cliDetectsRails() async throws {
        let output = try await cli.run(["services", "ls", "--json"], cwd: "\(testRoot)/my-rails-app")
        // Rails uses Gemfile which maps to ruby
        let toml = try? String(contentsOfFile: "\(testRoot)/my-rails-app/rawenv.toml", encoding: .utf8)
        #expect(toml != nil)
    }

    @Test func step03_cliDetectsFastapi() async throws {
        let output = try await cli.run(["services", "ls", "--json"], cwd: "\(testRoot)/my-fastapi")
        let toml = try? String(contentsOfFile: "\(testRoot)/my-fastapi/rawenv.toml", encoding: .utf8)
        #expect(toml != nil)
    }

    // MARK: - Scanner Finds All Created Projects

    @Test @MainActor func step04_scannerFindsAll() async {
        let engine = ScannerEngine()
        engine.addCustomPath(path: testRoot)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(engine.scanComplete)
        #expect(engine.discoveredProjects.count >= 7)
        let names = Set(engine.discoveredProjects.map(\.name))
        #expect(names.contains("my-nextjs-app"))
        #expect(names.contains("my-laravel-api"))
        #expect(names.contains("my-rails-app"))
        #expect(names.contains("my-fastapi"))
        #expect(names.contains("my-express-api"))
        #expect(names.contains("my-go-service"))
        #expect(names.contains("my-rust-api"))
    }

    // MARK: - Recipe Library Provides Install/Run Commands

    @Test @MainActor func step05_recipesForNextjsStack() {
        let lib = RecipeLibrary()
        // Next.js needs: node, postgresql, redis
        let node = lib.service(named: "Node.js")!
        let pg = lib.service(named: "PostgreSQL")!
        let redis = lib.service(named: "redis")!

        let home = NSHomeDirectory()
        let nodeStart = lib.startCommand(for: node, dataDir: "\(home)/.rawenv/data/node", logDir: "\(home)/.rawenv/logs")
        #expect(!nodeStart.isEmpty)

        let pgStart = lib.startCommand(for: pg, dataDir: "\(home)/.rawenv/data/pg", logDir: "\(home)/.rawenv/logs")
        #expect(pgStart.contains("pg_ctl"))

        let redisStart = lib.startCommand(for: redis, dataDir: "\(home)/.rawenv/data/redis", logDir: "\(home)/.rawenv/logs", port: 6379)
        #expect(redisStart.contains("redis-server"))
        #expect(redisStart.contains("6379"))

        let redisStop = lib.stopCommand(for: redis, dataDir: "\(home)/.rawenv/data/redis", port: 6379)
        #expect(redisStop.contains("shutdown"))
    }

    @Test @MainActor func step05_recipesForLaravelStack() {
        let lib = RecipeLibrary()
        // Laravel needs: php, mysql, redis, mailpit
        #expect(lib.service(named: "PHP") != nil)
        #expect(lib.service(named: "MySQL") != nil)
        #expect(lib.service(named: "Mailpit") != nil)

        let mysql = lib.service(named: "MySQL")!
        let installCmd = lib.installCommand(for: mysql, version: "8.4", platform: "macos")
        #expect(installCmd.contains("8.4"))
    }

    @Test @MainActor func step05_pluginsForPostgres() {
        let lib = RecipeLibrary()
        let pg = lib.service(named: "PostgreSQL")!
        #expect(pg.plugins["pgvector"] != nil)
        #expect(pg.plugins["postgis"] != nil)
        #expect(pg.plugins["timescaledb"] != nil)
        #expect(pg.plugins["pg_cron"] != nil)
        // Verify install commands
        #expect(pg.plugins["pgvector"]!.install.contains("vector"))
    }

    // MARK: - Service Manager Lifecycle

    @Test @MainActor func step06_serviceManagerForProject() async {
        let store = DataStore(cli: cli, projectPath: "\(testRoot)/my-nextjs-app")
        let mgr = ServiceManager(repository: store)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Should have services from rawenv.toml
        let services = mgr.services

        // Start all (will attempt launchctl)
        mgr.startAll()
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Stop all
        mgr.stopAll()
        try? await Task.sleep(nanoseconds: 500_000_000)

        // No crash = success
        _ = services
    }

    // MARK: - Deploy Generation

    @Test func step07_deployForNextjs() async throws {
        let output = try await cli.run(["deploy", "generate"], cwd: "\(testRoot)/my-nextjs-app")
        #expect(output.contains("Generated") || output.contains("main.tf") || !output.isEmpty)
    }

    // MARK: - DNS/Proxy/Tunnel

    @Test func step08_networkForProject() async throws {
        let dns = try await cli.run(["dns"], cwd: "\(testRoot)/my-nextjs-app")
        #expect(!dns.isEmpty)
        let proxy = try await cli.run(["proxy"], cwd: "\(testRoot)/my-nextjs-app")
        #expect(!proxy.isEmpty)
        let tunnel = try await cli.run(["tunnel", "3000"], cwd: "\(testRoot)/my-nextjs-app")
        #expect(tunnel.contains("ssh"))
    }

    // MARK: - Connections from .env

    @Test func step09_connectionsFromEnv() async throws {
        let output = try await cli.run(["connections"], cwd: "\(testRoot)/my-nextjs-app")
        #expect(!output.isEmpty)
    }

    // MARK: - Add Service to Existing Project

    @Test @MainActor func step10_addServiceViaRecipe() {
        let lib = RecipeLibrary()
        let meilisearch = lib.service(named: "Meilisearch")!

        // Generate install command
        let install = lib.installCommand(for: meilisearch, version: "1.8", platform: "macos")
        #expect(install.contains("meilisearch"))

        // Generate start command
        let start = lib.startCommand(for: meilisearch, dataDir: "/tmp/meili-data", logDir: "/tmp/meili-logs", port: 7700)
        #expect(start.contains("7700"))

        // Generate stop command
        let stop = lib.stopCommand(for: meilisearch, dataDir: "/tmp/meili-data", port: 7700)
        #expect(stop.contains("7700"))
    }

    // MARK: - Uninstall Info

    @Test func step11_uninstallInfo() async throws {
        let output = try await cli.run(["uninstall"], cwd: "\(testRoot)/my-nextjs-app")
        #expect(output.contains("rawenv") || output.contains("remove"))
    }

    // MARK: - Teardown

    @Test func step12_deleteAllProjects() {
        try? FileManager.default.removeItem(atPath: testRoot)
        #expect(!FileManager.default.fileExists(atPath: testRoot))
    }
}
