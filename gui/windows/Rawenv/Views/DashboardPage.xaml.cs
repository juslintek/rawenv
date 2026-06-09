using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Rawenv.ViewModels;

namespace Rawenv.Views;

public sealed partial class DashboardPage : Page
{
    public DashboardViewModel ViewModel { get; }

    public DashboardPage()
    {
        ViewModel = App.Services.GetRequiredService<DashboardViewModel>();
        InitializeComponent();
        ServicesList.ItemsSource = ViewModel.ServiceManager.Services;
        ViewModel.ServiceManager.PropertyChanged += ServiceManager_PropertyChanged;
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        await ViewModel.LoadAsync();
        UpdateStats();
    }

    private void ServiceManager_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(Services.MockServiceManager.RunningCount) or nameof(Services.MockServiceManager.TotalCpu) or nameof(Services.MockServiceManager.TotalMem))
            UpdateStats();
    }

    private void UpdateStats()
    {
        var sm = ViewModel.ServiceManager;
        RunningCount.Text = $"{sm.RunningCount} / {sm.Services.Count}";
        CpuLabel.Text = sm.TotalCpu;
        MemLabel.Text = sm.TotalMem;
        if (double.TryParse(sm.TotalCpu.TrimEnd('%'), out var cpu)) CpuBar.Value = cpu;
        if (double.TryParse(sm.TotalMem.Replace(" MB", ""), out var mem)) MemBar.Value = mem / 10;
    }

    private void StartAll_Click(object sender, RoutedEventArgs e) => ViewModel.ServiceManager.StartAll();
    private void StopAll_Click(object sender, RoutedEventArgs e) => ViewModel.ServiceManager.StopAll();

    private void ToggleService_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string name)
        {
            var idx = Enumerable.Range(0, ViewModel.ServiceManager.Services.Count)
                .FirstOrDefault(i => ViewModel.ServiceManager.Services[i].Name == name, -1);
            if (idx < 0) return;
            if (ViewModel.ServiceManager.Services[idx].Status == "running")
                ViewModel.ServiceManager.StopService(name);
            else
                ViewModel.ServiceManager.StartService(name);
        }
    }
}
