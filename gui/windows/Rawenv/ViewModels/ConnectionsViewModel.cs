using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Rawenv.Interfaces;
using Rawenv.Models;

namespace Rawenv.ViewModels;

public partial class ConnectionsViewModel : ObservableObject
{
    private readonly IDataRepository _repository;
    public ObservableCollection<Connection> Connections { get; } = new();

    [ObservableProperty] private string _selectedMode = "Local";

    public ConnectionsViewModel(IDataRepository repository)
    {
        _repository = repository;
    }

    [RelayCommand]
    public async Task LoadAsync()
    {
        var conns = await _repository.FetchConnectionsAsync();
        Connections.Clear();
        foreach (var c in conns) Connections.Add(c);
    }
}
