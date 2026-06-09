using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Rawenv.Interfaces;
using Rawenv.Models;
using Rawenv.Services;

namespace Rawenv.ViewModels;

public partial class ProjectsViewModel : ObservableObject
{
    private readonly IDataRepository _repository;
    public MockScannerEngine Scanner { get; }

    [ObservableProperty] private Project? _selectedProject;

    public ProjectsViewModel(IDataRepository repository, MockScannerEngine scanner)
    {
        _repository = repository;
        Scanner = scanner;
    }

    [RelayCommand]
    public async Task LoadAsync()
    {
        if (Scanner.DiscoveredProjects.Count == 0)
        {
            var projects = await _repository.FetchProjectsAsync();
            foreach (var p in projects) Scanner.DiscoveredProjects.Add(p);
        }
    }

    [RelayCommand]
    public void Discover() => Scanner.StartScan();
}
