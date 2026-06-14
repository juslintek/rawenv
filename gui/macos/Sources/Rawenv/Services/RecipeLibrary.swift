import Foundation

public struct ServiceRecipe: Codable, Identifiable, Equatable {
    public var id: String { name.lowercased().replacingOccurrences(of: " ", with: "-") }
    public let name: String
    public let category: String
    public let description: String
    public let icon: String
    public let versions: [String]
    public let default_version: String
    public let default_port: Int
    public let install: [String: String]
    public let start: String
    public let stop: String
    public let `init`: String?
    public let config_file: String?
    public let config_defaults: [String: String]
    public let plugins: [String: PluginRecipe]
}

public struct PluginRecipe: Codable, Identifiable, Equatable {
    public var id: String { "\(version)-\(description.prefix(10))" }
    public let version: String
    public let install: String
    public let description: String
}

public struct RecipeIndex: Codable {
    public let version: String
    public let catalogs: [String]
    public let all_services: [String]
    public let categories: [String: CategoryInfo]
}

public struct CategoryInfo: Codable {
    public let label: String
    public let icon: String
}

private struct RecipeCatalog: Codable {
    let services: [String: ServiceRecipe]
}

@MainActor
public final class RecipeLibrary: ObservableObject {
    @Published public var recipes: [ServiceRecipe] = []
    @Published public var categories: [String: CategoryInfo] = [:]

    public init() {
        loadRecipes()
    }

    public func service(named name: String) -> ServiceRecipe? {
        recipes.first { $0.name.lowercased() == name.lowercased() || $0.id == name.lowercased() }
    }

    public func services(in category: String) -> [ServiceRecipe] {
        recipes.filter { $0.category == category }
    }

    public func installCommand(for recipe: ServiceRecipe, version: String? = nil, platform: String = "macos") -> String
    {
        let ver = version ?? recipe.default_version
        let cmd = recipe.install[platform] ?? recipe.install["macos"] ?? ""
        return cmd.replacingOccurrences(of: "{version}", with: ver)
    }

    public func startCommand(for recipe: ServiceRecipe, dataDir: String, logDir: String, port: Int? = nil) -> String {
        recipe.start
            .replacingOccurrences(of: "{data_dir}", with: dataDir)
            .replacingOccurrences(of: "{log_dir}", with: logDir)
            .replacingOccurrences(of: "{port}", with: "\(port ?? recipe.default_port)")
            .replacingOccurrences(of: "{config_file}", with: recipe.config_file ?? "")
    }

    public func stopCommand(for recipe: ServiceRecipe, dataDir: String, port: Int? = nil) -> String {
        recipe.stop
            .replacingOccurrences(of: "{data_dir}", with: dataDir)
            .replacingOccurrences(of: "{port}", with: "\(port ?? recipe.default_port)")
    }

    private func loadRecipes() {
        let catalogFiles = [
            "databases.json", "caches-queues-search.json", "runtimes-monitoring-misc.json", "frameworks.json",
            "cms-ecommerce.json", "selfhosted.json", "forums-erp-crm.json",
        ]
        let searchPaths = [
            Bundle.main.resourcePath,
            "\(FileManager.default.currentDirectoryPath)/shared/recipes",
            "\(FileManager.default.currentDirectoryPath)/../../shared/recipes",
            "/Volumes/Projects/rawenv/shared/recipes",
            "\(NSHomeDirectory())/.rawenv/recipes",
        ].compactMap { $0 }

        // Load index for categories
        for base in searchPaths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: "\(base)/index.json")),
                let index = try? JSONDecoder().decode(RecipeIndex.self, from: data)
            {
                categories = index.categories
                break
            }
        }

        // Load catalogs
        for file in catalogFiles {
            for base in searchPaths {
                let path = "\(base)/\(file)"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                    let catalog = try? JSONDecoder().decode(RecipeCatalog.self, from: data)
                else { continue }
                recipes.append(contentsOf: catalog.services.values)
                break
            }
        }

        recipes.sort { $0.name < $1.name }
    }
}
