# macOS Architecture — SwiftUI

## Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI |
| Reactivity | Combine |
| Architecture | MVVM |
| Project | Swift Package (Package.swift) |
| Testing | XCTest (unit) + XCUITest (e2e) |

## Directory Structure

```
gui/macos/
├── Package.swift
├── Sources/Rawenv/
│   ├── App/
│   │   ├── RawenvApp.swift          # @main entry, DI setup
│   │   └── AppState.swift           # App-wide observable state
│   ├── Models/
│   │   ├── Service.swift
│   │   ├── LogEntry.swift
│   │   └── AIAction.swift
│   ├── Protocols/
│   │   ├── DataRepository.swift     # Data access contract
│   │   ├── NavigationService.swift  # Routing contract
│   │   └── AIProvider.swift         # AI interaction contract
│   ├── Services/
│   │   ├── MockDataRepository.swift
│   │   ├── MockAIProvider.swift
│   │   └── LiveDataRepository.swift
│   ├── ViewModels/
│   │   ├── DashboardVM.swift
│   │   ├── SettingsVM.swift
│   │   ├── ServicesVM.swift
│   │   └── AIChatVM.swift
│   └── Views/
│       ├── Dashboard/
│       ├── Settings/
│       ├── Services/
│       └── AIChat/
└── Tests/
    ├── RawenvUnitTests/             # Unit tests (VMs, models, views — headless, fast)
    │   ├── DashboardVMTests.swift
    │   ├── SettingsVMTests.swift
    │   └── TestHelpers.swift        # shared test doubles
    ├── RawenvIntegrationTests/      # Integration tests (real rawenv binary boundary)
    │   └── IntegrationTests.swift
    ├── RawenvE2ETests/              # E2E tests (full lifecycle, real services; incl. UIE2ETests)
    │   ├── ServiceValidationTests.swift
    │   └── UIE2ETests.swift         # ⚠ drives the GUI via Accessibility — takes over the screen
    └── RawenvUITests/               # XCUITest e2e (xcodebuild only)
        ├── Pages/                   # Page Objects
        │   ├── DashboardPage.swift
        │   └── SettingsPage.swift
        └── DashboardE2ETests.swift
```

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Types (struct, class, enum, protocol) | PascalCase | `DashboardViewModel`, `DataRepository` |
| Properties, methods, variables | camelCase | `serviceList`, `fetchServices()` |
| Files | Match type name | `DashboardVM.swift` |

## Protocols

```swift
protocol DataRepository {
    func fetchServices() async throws -> [Service]
    func fetchLogs(for service: Service) async throws -> [LogEntry]
}

protocol NavigationService {
    func navigate(to destination: Destination)
    func goBack()
}

protocol AIProvider {
    func send(prompt: String) async throws -> AIResponse
    func cancel()
    var autonomyLevel: AIAutonomyLevel { get set }
}
```

All protocols have mock implementations for testing and preview.

## Patterns Used

| Pattern | Implementation |
|---------|---------------|
| Observer | `@Published` properties + Combine pipelines |
| Strategy | Protocol conformance (`AIProvider` with multiple implementations) |
| Repository | `DataRepository` protocol abstracts data source |
| Command | AI actions as `AICommand` objects with `execute()` / `undo()` |
| Factory Method | View creation via `ViewFactory` for platform-specific variants |
| Mediator | `NavigationService` mediates between views |

## Testing

### Unit Tests (XCTest)

- Every ViewModel method tested with mock dependencies
- Mock data loaded from `shared/mock-data.json`
- No UI framework dependency in ViewModel tests

### E2E Tests (XCUITest)

- `.accessibilityIdentifier` on ALL interactive elements
- Page Object pattern for test organization:

```swift
struct DashboardPage {
    let app: XCUIApplication

    var servicesList: XCUIElement {
        app.tables["dashboard_services_list"]
    }

    func tapService(named name: String) -> ServiceDetailPage {
        servicesList.cells[name].tap()
        return ServiceDetailPage(app: app)
    }
}
```

## Dependency Injection

```swift
@main
struct RawenvApp: App {
    @StateObject private var appState: AppState

    init() {
        let repository: DataRepository = LiveDataRepository()
        let aiProvider: AIProvider = LiveAIProvider()
        _appState = StateObject(wrappedValue: AppState(
            repository: repository,
            aiProvider: aiProvider
        ))
    }
}
```

Swap `Live*` for `Mock*` in previews and tests.
