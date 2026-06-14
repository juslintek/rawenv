import Foundation
import Testing

@testable import RawenvLib

/// Tests migrating existing services to rawenv and adding new services to existing projects.

private let testRoot = "/tmp/rawenv-migration-test"
private let cli = RawenvCLI(
    binaryPath: resolvedRawenvBinary())

@Suite(.serialized) struct ServiceMigrationTests {

    // MARK: - Setup

    @Test func step00_setup() throws {
        try? FileManager.default.removeItem(atPath: testRoot)
        try FileManager.default.createDirectory(atPath: testRoot, withIntermediateDirectories: true)
    }

    // MARK: - Simulate existing project with system-installed services

    @Test func step01_createExistingProject() throws {
        let dir = "\(testRoot)/existing-app"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Project already has package.json (existing Node app)
        try """
        {"name":"existing-app","version":"2.1.0","engines":{"node":">=20"},"dependencies":{"express":"^4","pg":"^8","redis":"^4","bull":"^4"}}
        """.write(toFile: "\(dir)/package.json", atomically: true, encoding: .utf8)
        // Has .env pointing to system-installed services
        try """
        DATABASE_URL=postgres://localhost:5432/existing_app
        REDIS_URL=redis://localhost:6379
        ELASTICSEARCH_URL=http://localhost:9200
        S3_ENDPOINT=https://s3.amazonaws.com
        SMTP_HOST=smtp.sendgrid.net
        QUEUE_URL=redis://localhost:6379/1
        """.write(toFile: "\(dir)/.env", atomically: true, encoding: .utf8)
        // Has docker-compose.yml (services to migrate FROM)
        try """
        version: '3.8'
        services:
          postgres:
            image: postgres:16
            ports: ["5432:5432"]
          redis:
            image: redis:7-alpine
            ports: ["6379:6379"]
          elasticsearch:
            image: elasticsearch:8.13.0
            ports: ["9200:9200"]
        """.write(toFile: "\(dir)/docker-compose.yml", atomically: true, encoding: .utf8)
    }

    // MARK: - Detect existing project

    @Test func step02_detectExistingProject() async throws {
        let output = try await cli.run(["init"], cwd: "\(testRoot)/existing-app")
        #expect(output.contains("rawenv.toml") || output.contains("Created") || output.contains("already exists"))
        let toml = try String(contentsOfFile: "\(testRoot)/existing-app/rawenv.toml", encoding: .utf8)
        #expect(!toml.isEmpty)
    }

    @Test func step02_servicesDetected() async throws {
        struct S: Decodable {
            let name: String
            let port: Int
            let status: String
        }
        let services: [S] = try await cli.runJSON(["services", "ls"], as: [S].self, cwd: "\(testRoot)/existing-app")
        #expect(!services.isEmpty)
        // Should detect postgres and redis from .env
        let names = services.map(\.name)
        #expect(names.contains("postgres") || names.contains("postgresql"))
        #expect(names.contains("redis"))
    }

    // MARK: - Migration: replace Docker services with rawenv-managed

    @Test @MainActor func step03_migrationRecipesAvailable() {
        let lib = RecipeLibrary()
        // All services from docker-compose should have rawenv recipes
        #expect(lib.service(named: "PostgreSQL") != nil)
        #expect(lib.service(named: "redis") != nil)
        #expect(lib.service(named: "Elasticsearch") != nil)
    }

    @Test @MainActor func step03_migrationGeneratesCommands() {
        let lib = RecipeLibrary()
        let home = NSHomeDirectory()
        let dataDir = "\(home)/.rawenv/data"

        // PostgreSQL migration
        let pg = lib.service(named: "PostgreSQL")!
        let pgInstall = lib.installCommand(for: pg, version: "16", platform: "macos")
        #expect(pgInstall.contains("16"))
        let pgStart = lib.startCommand(for: pg, dataDir: "\(dataDir)/postgres", logDir: "\(home)/.rawenv/logs")
        #expect(pgStart.contains("pg_ctl"))
        let pgStop = lib.stopCommand(for: pg, dataDir: "\(dataDir)/postgres")
        #expect(pgStop.contains("pg_ctl") || pgStop.contains("stop"))

        // Redis migration
        let redis = lib.service(named: "redis")!
        let redisInstall = lib.installCommand(for: redis, version: "7.4", platform: "macos")
        #expect(redisInstall.contains("redis"))
        let redisStart = lib.startCommand(
            for: redis, dataDir: "\(dataDir)/redis", logDir: "\(home)/.rawenv/logs", port: 6379)
        #expect(redisStart.contains("6379"))

        // Elasticsearch migration
        let es = lib.service(named: "Elasticsearch")!
        let esInstall = lib.installCommand(for: es, version: "8.13", platform: "macos")
        #expect(esInstall.contains("8.13"))
        let esStart = lib.startCommand(
            for: es, dataDir: "\(dataDir)/elasticsearch", logDir: "\(home)/.rawenv/logs", port: 9200)
        #expect(esStart.contains("elasticsearch"))
    }

    @Test @MainActor func step03_migrationConfigDefaults() {
        let lib = RecipeLibrary()
        let pg = lib.service(named: "PostgreSQL")!
        // Verify optimized config defaults for dev
        #expect(pg.config_defaults["max_connections"] == "20")
        #expect(pg.config_defaults["shared_buffers"] == "64MB")

        let redis = lib.service(named: "redis")!
        #expect(redis.config_defaults["maxmemory"] == "64mb")

        let es = lib.service(named: "Elasticsearch")!
        #expect(es.config_defaults["discovery.type"] == "single-node")
    }

    // MARK: - Add new service to existing project

    @Test @MainActor func step04_addMeilisearch() {
        let lib = RecipeLibrary()
        let meili = lib.service(named: "Meilisearch")!
        #expect(meili.default_port == 7700)
        let install = lib.installCommand(for: meili, version: "1.8", platform: "macos")
        #expect(install.contains("meilisearch"))
        let start = lib.startCommand(for: meili, dataDir: "/tmp/meili", logDir: "/tmp/logs", port: 7700)
        #expect(start.contains("7700"))
        let stop = lib.stopCommand(for: meili, dataDir: "/tmp/meili", port: 7700)
        #expect(!stop.isEmpty)
    }

    @Test @MainActor func step04_addRabbitMQ() {
        let lib = RecipeLibrary()
        let rmq = lib.service(named: "RabbitMQ")!
        #expect(rmq.default_port == 5672)
        #expect(rmq.plugins["management"] != nil)
        #expect(rmq.plugins["management"]!.install.contains("enable"))
        let install = lib.installCommand(for: rmq, version: "3.13", platform: "macos")
        #expect(install.contains("rabbitmq"))
    }

    @Test @MainActor func step04_addMinIO() {
        let lib = RecipeLibrary()
        let minio = lib.service(named: "MinIO")!
        #expect(minio.default_port == 9000)
        let start = lib.startCommand(for: minio, dataDir: "/tmp/minio-data", logDir: "/tmp/logs", port: 9000)
        #expect(start.contains("MINIO_ROOT_USER"))
        #expect(start.contains("9000"))
    }

    @Test @MainActor func step04_addMailpit() {
        let lib = RecipeLibrary()
        let mail = lib.service(named: "Mailpit")!
        #expect(mail.default_port == 8025)
        let start = lib.startCommand(for: mail, dataDir: "/tmp/mail", logDir: "/tmp/logs", port: 8025)
        #expect(start.contains("8025"))
        #expect(start.contains("1025"))  // SMTP port
    }

    @Test @MainActor func step04_addGrafanaWithPrometheus() {
        let lib = RecipeLibrary()
        let prom = lib.service(named: "Prometheus")!
        let graf = lib.service(named: "Grafana")!
        #expect(prom.default_port == 9090)
        #expect(graf.default_port == 3001)
        // Grafana has plugins
        #expect(graf.plugins["redis-datasource"] != nil)
    }

    // MARK: - Add self-hosted services

    @Test @MainActor func step05_addKeycloak() {
        let lib = RecipeLibrary()
        let kc = lib.service(named: "Keycloak")
        #expect(kc != nil)
        #expect(kc?.category == "auth")
    }

    @Test @MainActor func step05_addN8n() {
        let lib = RecipeLibrary()
        let n8n = lib.service(named: "n8n")
        #expect(n8n != nil)
        #expect(n8n?.category == "workflow")
    }

    @Test @MainActor func step05_addGitea() {
        let lib = RecipeLibrary()
        let gitea = lib.service(named: "Gitea")
        #expect(gitea != nil)
        #expect(gitea?.category == "selfhosted")
    }

    // MARK: - Verify service can be added to rawenv.toml

    @Test func step06_addServiceToToml() throws {
        let tomlPath = "\(testRoot)/existing-app/rawenv.toml"
        var toml = try String(contentsOfFile: tomlPath, encoding: .utf8)
        // Add meilisearch service
        toml += "\n[services.meilisearch]\nversion = \"1.8\"\n"
        try toml.write(toFile: tomlPath, atomically: true, encoding: .utf8)
        let updated = try String(contentsOfFile: tomlPath, encoding: .utf8)
        #expect(updated.contains("meilisearch"))
        #expect(updated.contains("1.8"))
    }

    @Test func step06_verifyNewServiceInList() async throws {
        struct S: Decodable {
            let name: String
            let port: Int
        }
        let services: [S] = try await cli.runJSON(["services", "ls"], as: [S].self, cwd: "\(testRoot)/existing-app")
        let names = services.map(\.name)
        #expect(names.contains("meilisearch"))
    }

    // MARK: - Service Manager handles new service

    @Test @MainActor func step07_serviceManagerSeesNewService() async {
        let store = DataStore(cli: cli, projectPath: "\(testRoot)/existing-app")
        let mgr = ServiceManager(repository: store)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let names = mgr.services.map(\.name)
        #expect(names.contains("meilisearch"))
    }

    @Test @MainActor func step07_startStopNewService() async {
        let store = DataStore(cli: cli, projectPath: "\(testRoot)/existing-app")
        let mgr = ServiceManager(repository: store)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        // Start meilisearch (will attempt launchctl - won't actually start without binary)
        mgr.startService(name: "meilisearch")
        try? await Task.sleep(nanoseconds: 300_000_000)
        mgr.stopService(name: "meilisearch")
        try? await Task.sleep(nanoseconds: 300_000_000)
        // No crash = success
    }

    // MARK: - Connections update after adding service

    @Test func step08_connectionsAfterMigration() async throws {
        // Add MEILISEARCH_URL to .env
        let envPath = "\(testRoot)/existing-app/.env"
        var env = try String(contentsOfFile: envPath, encoding: .utf8)
        env += "MEILISEARCH_URL=http://localhost:7700\n"
        try env.write(toFile: envPath, atomically: true, encoding: .utf8)

        let output = try await cli.run(["connections"], cwd: "\(testRoot)/existing-app")
        #expect(!output.isEmpty)
    }

    // MARK: - Deploy regeneration after adding service

    @Test func step09_deployRegeneratesWithNewService() async throws {
        let output = try await cli.run(["deploy", "generate"], cwd: "\(testRoot)/existing-app")
        #expect(!output.isEmpty)
    }

    // MARK: - Plugin installation for migrated service

    @Test @MainActor func step10_installPluginForPostgres() {
        let lib = RecipeLibrary()
        let pg = lib.service(named: "PostgreSQL")!

        // Install pgvector for AI embeddings
        let pgvector = pg.plugins["pgvector"]!
        #expect(pgvector.install.contains("vector"))
        #expect(pgvector.description.contains("Vector"))

        // Install timescaledb for time-series
        let ts = pg.plugins["timescaledb"]!
        #expect(ts.install.contains("timescaledb"))

        // Install pg_cron for scheduled jobs
        let cron = pg.plugins["pg_cron"]!
        #expect(cron.install.contains("pg_cron"))
    }

    @Test @MainActor func step10_installPluginForRedis() {
        let lib = RecipeLibrary()
        let redis = lib.service(named: "redis")!

        let search = redis.plugins["redisearch"]!
        #expect(search.install.contains("redisearch"))

        let json = redis.plugins["redisjson"]!
        #expect(json.install.contains("rejson"))

        let bloom = redis.plugins["redisbloom"]!
        #expect(bloom.description.contains("Bloom"))
    }

    // MARK: - Cleanup

    @Test func step11_cleanup() {
        try? FileManager.default.removeItem(atPath: testRoot)
        #expect(!FileManager.default.fileExists(atPath: testRoot))
    }
}
