import Foundation
import Testing

@testable import RawenvLib

@Suite struct RecipeLibraryTests {
    @Test @MainActor func loadsRecipes() {
        let lib = RecipeLibrary()
        #expect(lib.recipes.count >= 20)
    }

    @Test @MainActor func loadsCategories() {
        let lib = RecipeLibrary()
        #expect(!lib.categories.isEmpty)
        #expect(lib.categories["database"] != nil)
        #expect(lib.categories["cache"] != nil)
        #expect(lib.categories["queue"] != nil)
    }

    @Test @MainActor func findServiceByName() {
        let lib = RecipeLibrary()
        let pg = lib.service(named: "PostgreSQL")
        #expect(pg != nil)
        #expect(pg?.default_port == 5432)
        #expect(pg?.category == "database")
    }

    @Test @MainActor func findServiceById() {
        let lib = RecipeLibrary()
        let redis = lib.service(named: "redis")
        #expect(redis != nil)
        #expect(redis?.default_port == 6379)
    }

    @Test @MainActor func filterByCategory() {
        let lib = RecipeLibrary()
        let dbs = lib.services(in: "database")
        #expect(dbs.count >= 4)
        #expect(dbs.allSatisfy { $0.category == "database" })
    }

    @Test @MainActor func installCommand() {
        let lib = RecipeLibrary()
        guard let redis = lib.service(named: "redis") else {
            Issue.record("Redis not found")
            return
        }
        let cmd = lib.installCommand(for: redis, version: "7.4", platform: "macos")
        #expect(cmd.contains("7.4"))
        #expect(cmd.contains("redis"))
    }

    @Test @MainActor func startCommand() {
        let lib = RecipeLibrary()
        guard let redis = lib.service(named: "redis") else {
            Issue.record("Redis not found")
            return
        }
        let cmd = lib.startCommand(for: redis, dataDir: "/tmp/data", logDir: "/tmp/logs", port: 6380)
        #expect(cmd.contains("/tmp/data"))
        #expect(cmd.contains("6380"))
    }

    @Test @MainActor func stopCommand() {
        let lib = RecipeLibrary()
        guard let redis = lib.service(named: "redis") else {
            Issue.record("Redis not found")
            return
        }
        let cmd = lib.stopCommand(for: redis, dataDir: "/tmp/data", port: 6380)
        #expect(cmd.contains("6380"))
    }

    @Test @MainActor func pluginsExist() {
        let lib = RecipeLibrary()
        guard let pg = lib.service(named: "PostgreSQL") else {
            Issue.record("PG not found")
            return
        }
        #expect(!pg.plugins.isEmpty)
        #expect(pg.plugins["pgvector"] != nil)
        #expect(pg.plugins["pgvector"]?.description.contains("Vector") == true)
    }

    @Test @MainActor func allServicesHaveRequiredFields() {
        let lib = RecipeLibrary()
        for recipe in lib.recipes {
            #expect(!recipe.name.isEmpty, "Service \(recipe.id) missing name")
            #expect(!recipe.category.isEmpty, "Service \(recipe.name) missing category")
            #expect(!recipe.versions.isEmpty, "Service \(recipe.name) missing versions")
            #expect(!recipe.icon.isEmpty, "Service \(recipe.name) missing icon")
        }
    }

    @Test @MainActor func versionsAreValid() {
        let lib = RecipeLibrary()
        for recipe in lib.recipes {
            #expect(
                recipe.versions.contains(recipe.default_version), "\(recipe.name) default_version not in versions list")
        }
    }
}
