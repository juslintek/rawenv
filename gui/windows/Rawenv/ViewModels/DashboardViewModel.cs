using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Rawenv.Interfaces;
using Rawenv.Models;
using Rawenv.Services;

namespace Rawenv.ViewModels;

public partial class DashboardViewModel : ObservableObject
{
    private readonly IDataRepository _repository;
    public MockServiceManager ServiceManager { get; }

    public ObservableCollection<LogEntry> Logs { get; } = new();
    public ObservableCollection<Connection> Connections { get; } = new();

    [ObservableProperty] private string _cellInfo = "AppContainer isolation active. Memory: 256MB limit.";
    [ObservableProperty] private string _backupInfo = "Last backup: 2h ago. 3 snapshots available.";
    [ObservableProperty] private string _configContent = "[services.postgres]\nversion = \"18.2\"\nport = 5432\nmax_connections = 20\n\n[services.redis]\nversion = \"7.4\"\nport = 6379\n\n[services.meilisearch]\nversion = \"1.12\"\nport = 7700";

    public DashboardViewModel(IDataRepository repository, MockServiceManager serviceManager)
    {
        _repository = repository;
        ServiceManager = serviceManager;
    }

    [RelayCommand]
    public async Task LoadAsync()
    {
        var logs = await _repository.FetchLogsAsync();
        Logs.Clear();
        foreach (var l in logs) Logs.Add(l);

        var conns = await _repository.FetchConnectionsAsync();
        Connections.Clear();
        foreach (var c in conns) Connections.Add(c);
    }
}
