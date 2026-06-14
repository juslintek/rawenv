import Foundation

public struct FrameworkTemplate: Codable, Identifiable, Equatable {
    public var id: String { name.lowercased().replacingOccurrences(of: " ", with: "-") }
    public let name: String
    public let language: String
    public let category: String
    public let icon: String
    public let description: String
    public let services: [String]
    public let files: [String: String]
}

private struct TemplateCatalog: Codable {
    let templates: [String: FrameworkTemplate]
}

@MainActor
public final class ProjectCreator: ObservableObject {
    @Published public var templates: [FrameworkTemplate] = []
    @Published public var isCreating = false
    @Published public var createdPath: String?
    @Published public var error: String?

    private let cli: RawenvCLI

    public init(cli: RawenvCLI = RawenvCLI()) {
        self.cli = cli
        loadTemplates()
    }

    public func create(template: FrameworkTemplate, name: String, parentDir: String) async {
        isCreating = true
        error = nil
        createdPath = nil
        let projectDir = "\(parentDir)/\(name)"
        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

            for (filename, content) in template.files {
                let rendered =
                    content
                    .replacingOccurrences(of: "{project_name}", with: name)
                    .replacingOccurrences(of: "{project_name_camel}", with: name.capitalized)
                let filePath = "\(projectDir)/\(filename)"
                let dir = (filePath as NSString).deletingLastPathComponent
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try rendered.write(toFile: filePath, atomically: true, encoding: .utf8)
            }

            // Run rawenv init to generate rawenv.toml
            _ = try? await cli.run(["init"], cwd: projectDir)

            createdPath = projectDir
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }

    public func templatesByCategory() -> [(category: String, templates: [FrameworkTemplate])] {
        let grouped = Dictionary(grouping: templates, by: \.category)
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func loadTemplates() {
        let searchPaths = [
            "\(FileManager.default.currentDirectoryPath)/shared/recipes",
            "/Volumes/Projects/rawenv/shared/recipes",
            "\(NSHomeDirectory())/.rawenv/recipes",
        ]
        for base in searchPaths {
            let path = "\(base)/templates.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                let catalog = try? JSONDecoder().decode(TemplateCatalog.self, from: data)
            else { continue }
            templates = Array(catalog.templates.values).sorted { $0.name < $1.name }
            return
        }
    }
}
