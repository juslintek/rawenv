using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Rawenv.Interfaces;
using Rawenv.Services;
using Rawenv.ViewModels;
using Rawenv.Views;

namespace Rawenv;

public partial class App : Application
{
    public static IServiceProvider Services { get; private set; } = null!;
    private Window? _window;

    public App()
    {
        var sc = new ServiceCollection();

        // Core services
        sc.AddSingleton<IDataRepository, MockDataRepository>();
        sc.AddSingleton<INavigationService, NavigationService>();
        sc.AddSingleton<IAIProvider, MockAIProvider>();

        // Stateful mock engines
        sc.AddSingleton<MockServiceManager>();
        sc.AddSingleton<MockInstallerEngine>();
        sc.AddSingleton<MockScannerEngine>();
        sc.AddSingleton<MockDeployEngine>();

        // ViewModels
        sc.AddTransient<DashboardViewModel>();
        sc.AddTransient<SettingsViewModel>();
        sc.AddTransient<AIChatViewModel>();
        sc.AddTransient<ConnectionsViewModel>();
        sc.AddTransient<DeployViewModel>();
        sc.AddTransient<InstallerViewModel>();
        sc.AddTransient<ProjectsViewModel>();

        Services = sc.BuildServiceProvider();
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}
