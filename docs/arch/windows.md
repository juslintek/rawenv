# Windows Architecture — WinUI 3

## Stack

| Layer | Technology |
|-------|-----------|
| Language | C# / .NET 8 |
| UI Framework | WinUI 3 (Windows App SDK) |
| MVVM Toolkit | CommunityToolkit.Mvvm |
| Architecture | MVVM |
| DI | Microsoft.Extensions.DependencyInjection |
| Testing | MSTest (unit) + WinAppDriver/Appium (e2e) |

## Directory Structure

```
gui/windows/
├── Rawenv.sln
├── Rawenv/
│   ├── Rawenv.csproj
│   ├── App.xaml.cs                       # DI container setup
│   ├── Models/
│   │   ├── Service.cs
│   │   ├── LogEntry.cs
│   │   └── AIAction.cs
│   ├── Interfaces/
│   │   ├── IDataRepository.cs
│   │   ├── INavigationService.cs
│   │   └── IAIProvider.cs
│   ├── Services/
│   │   ├── MockDataRepository.cs
│   │   ├── MockAIProvider.cs
│   │   ├── LiveDataRepository.cs
│   │   └── NavigationService.cs
│   ├── ViewModels/
│   │   ├── DashboardViewModel.cs
│   │   ├── SettingsViewModel.cs
│   │   ├── ServicesViewModel.cs
│   │   └── AIChatViewModel.cs
│   └── Views/
│       ├── DashboardPage.xaml / .xaml.cs
│       ├── SettingsPage.xaml / .xaml.cs
│       ├── ServicesPage.xaml / .xaml.cs
│       └── AIChatPage.xaml / .xaml.cs
├── Rawenv.Tests/                         # MSTest unit tests
│   ├── Rawenv.Tests.csproj
│   ├── DashboardViewModelTests.cs
│   └── MockDataRepositoryTests.cs
└── Rawenv.E2E/                           # WinAppDriver e2e
    ├── Rawenv.E2E.csproj
    ├── Pages/
    │   ├── DashboardPage.cs
    │   └── SettingsPage.cs
    └── DashboardE2ETests.cs
```

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes, methods, properties | PascalCase | `DashboardViewModel`, `FetchServices()` |
| Interfaces | I-prefix + PascalCase | `IDataRepository`, `INavigationService` |
| Private fields | _camelCase | `_repository`, `_navigationService` |
| Files | Match type name | `DashboardViewModel.cs` |
| XAML elements | x:Name in PascalCase | `ServicesList`, `SettingsButton` |

## Interfaces

```csharp
public interface IDataRepository
{
    Task<IReadOnlyList<Service>> FetchServicesAsync();
    Task<IReadOnlyList<LogEntry>> FetchLogsAsync(Service service);
}

public interface INavigationService
{
    void NavigateTo(string destination);
    void GoBack();
}

public interface IAIProvider
{
    Task<AIResponse> SendAsync(string prompt);
    void Cancel();
    AIAutonomyLevel AutonomyLevel { get; set; }
}
```

## Patterns Used

| Pattern | Implementation |
|---------|---------------|
| Observer | `ObservableObject` base, `INotifyPropertyChanged`, `ObservableCollection<T>` |
| Command | `RelayCommand` / `ICommand` for UI actions; `AICommand` for autonomous actions |
| Strategy | Interface implementations swapped via DI |
| Repository | `IDataRepository` abstracts data source |
| Mediator | `INavigationService` mediates between pages |
| Factory Method | Page/ViewModel creation via DI container |

## Dependency Injection (App.xaml.cs)

```csharp
public partial class App : Application
{
    public IServiceProvider Services { get; }

    public App()
    {
        Services = new ServiceCollection()
            .AddSingleton<IDataRepository, LiveDataRepository>()
            .AddSingleton<INavigationService, NavigationService>()
            .AddSingleton<IAIProvider, LiveAIProvider>()
            .AddTransient<DashboardViewModel>()
            .AddTransient<SettingsViewModel>()
            .BuildServiceProvider();

        InitializeComponent();
    }
}
```

Swap `Live*` for `Mock*` in test configurations.

## Testing

### Unit Tests (MSTest)

- ViewModels tested with mock interfaces
- Mock data loaded from `shared/mock-data.json`
- No UI framework dependency in ViewModel tests

```csharp
[TestClass]
public class DashboardViewModelTests
{
    [TestMethod]
    public async Task FetchServices_PopulatesList()
    {
        var repo = new MockDataRepository();
        var vm = new DashboardViewModel(repo);

        await vm.LoadCommand.ExecuteAsync(null);

        Assert.IsTrue(vm.Services.Count > 0);
    }
}
```

### E2E Tests (WinAppDriver + Appium)

- `AutomationProperties.AutomationId` on ALL interactive elements
- Page Object pattern:

```csharp
public class DashboardPage
{
    private readonly WindowsDriver<WindowsElement> _driver;

    public DashboardPage(WindowsDriver<WindowsElement> driver)
    {
        _driver = driver;
    }

    public WindowsElement ServicesList =>
        _driver.FindElementByAccessibilityId("DashboardServicesList");

    public ServiceDetailPage SelectService(string name)
    {
        ServicesList.FindElementByName(name).Click();
        return new ServiceDetailPage(_driver);
    }
}
```

## Build & Test

```bash
dotnet build Rawenv.sln
dotnet test Rawenv.Tests/
dotnet test Rawenv.E2E/    # requires WinAppDriver running
```
