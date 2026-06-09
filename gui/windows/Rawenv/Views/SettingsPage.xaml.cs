using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Rawenv.Interfaces;

namespace Rawenv.Views;

public sealed partial class SettingsPage : Page
{
    private readonly IDataRepository _repository;
    private readonly StackPanel[] _panels;

    public SettingsPage()
    {
        _repository = App.Services.GetRequiredService<IDataRepository>();
        InitializeComponent();
        _panels = [GeneralPanel, ServicesPanel, RuntimesPanel, NetworkPanel, CellsPanel, DeployPanel, AIPanel, ThemePanel, AboutPanel];
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        var settings = await _repository.FetchSettingsAsync();

        // General
        StoreLocationBox.Text = settings.General.StoreLocation;
        AutoStartToggle.IsOn = settings.General.AutoStartServices;
        AutoDetectToggle.IsOn = settings.General.AutoDetectProjects;
        LaunchAtLoginToggle.IsOn = settings.General.LaunchAtLogin;
        FileWatcherToggle.IsOn = settings.General.FileWatcher;
        ScanPathsBox.Text = string.Join("\n", settings.General.ScanPaths);

        // Network
        LocalDomainBox.Text = settings.Network.LocalDomain;
        AutoTlsToggle.IsOn = settings.Network.AutoTls;
        ProxyPortBox.Value = settings.Network.ProxyPort;
        TunnelProviderBox.Text = settings.Network.TunnelProvider;
        RelayServerBox.Text = settings.Network.RelayServer;

        // Cells
        CellsEnabledToggle.IsOn = settings.Cells.EnableByDefault;
        MemoryLimitBox.Text = settings.Cells.DefaultMemoryLimit;
        CpuLimitBox.Text = settings.Cells.DefaultCpuLimit;
        NetworkIsolationToggle.IsOn = settings.Cells.NetworkIsolation;

        // Deploy
        DeployProviderBox.Text = settings.Deploy.Provider;
        SshKeyBox.Text = settings.Deploy.SshKey;
        ContainerRuntimeBox.Text = settings.Deploy.ContainerRuntime;
        RegistryBox.Text = settings.Deploy.Registry;
        AutoGenerateToggle.IsOn = settings.Deploy.AutoGenerate;

        // AI
        AIProviderCombo.ItemsSource = settings.AI.Providers;
        AIProviderCombo.SelectedItem = settings.AI.Provider;
        ProactiveSuggestionsToggle.IsOn = settings.AI.ProactiveSuggestions;
        AutoApplySafeToggle.IsOn = settings.AI.AutoApplySafeFixes;
        IncludeLogsToggle.IsOn = settings.AI.IncludeLogsInContext;
        MaxContextBox.Value = settings.AI.MaxContextSize;

        // Autonomy
        AutonomyLevelCombo.ItemsSource = settings.AI.AutonomyLevels;
        AutonomyLevelCombo.SelectedItem = settings.AI.DefaultAutonomy;

        // BYOM
        CustomEndpointBox.Text = settings.AI.CustomEndpoint;

        // Theme
        AccentColorBox.Text = settings.Theme.AccentColor;
        RadiusSlider.Value = settings.Theme.BorderRadius;
        FontSizeBox.Value = settings.Theme.FontSize;
        SidebarWidthSlider.Value = settings.Theme.SidebarWidth;
    }

    private void SettingsNav_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SettingsNav.SelectedItem is not ListViewItem item) return;
        var tag = item.Tag?.ToString();
        string[] tags = ["General", "Services", "Runtimes", "Network", "Cells", "Deploy", "AI", "Theme", "About"];
        for (int i = 0; i < _panels.Length; i++)
            _panels[i].Visibility = tags[i] == tag ? Visibility.Visible : Visibility.Collapsed;
    }
}
