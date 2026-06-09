using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Rawenv.Models;
using Rawenv.Services;

namespace Rawenv.Views;

public sealed partial class ProjectsPage : Page
{
    private readonly MockScannerEngine _scanner;

    public ProjectsPage()
    {
        _scanner = App.Services.GetRequiredService<MockScannerEngine>();
        InitializeComponent();
        ProjectList.ItemsSource = _scanner.DiscoveredProjects;
        _scanner.PropertyChanged += Scanner_PropertyChanged;
        _scanner.DiscoveredProjects.CollectionChanged += (_, _) => UpdateCount();
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        if (_scanner.State == MockScannerEngine.ScanState.Idle && _scanner.DiscoveredProjects.Count == 0)
        {
            var repo = App.Services.GetRequiredService<Interfaces.IDataRepository>();
            var projects = await repo.FetchProjectsAsync();
            foreach (var p in projects) _scanner.DiscoveredProjects.Add(p);
        }
        UpdateCount();
    }

    private void Scanner_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(MockScannerEngine.State):
                ScanningPanel.Visibility = _scanner.State == MockScannerEngine.ScanState.Scanning
                    ? Visibility.Visible : Visibility.Collapsed;
                ScanButton.IsEnabled = _scanner.State != MockScannerEngine.ScanState.Scanning;
                break;
            case nameof(MockScannerEngine.Progress):
                ScanProgress.Value = _scanner.Progress;
                ScanPercent.Text = $"{_scanner.Progress * 100:F0}%";
                break;
            case nameof(MockScannerEngine.CurrentPath):
                ScanPath.Text = _scanner.CurrentPath;
                break;
        }
    }

    private void Scan_Click(object sender, RoutedEventArgs e) => _scanner.StartScan();

    private void ProjectList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ProjectList.SelectedItem is Project p)
        {
            SetupPanel.Visibility = Visibility.Visible;
            SetupProjectName.Text = p.Name;
            SetupProjectPath.Text = p.Path;
        }
        else
        {
            SetupPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateCount()
    {
        ProjectCountLabel.Text = $"{_scanner.DiscoveredProjects.Count} projects discovered";
    }
}
