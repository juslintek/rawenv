using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Rawenv.Interfaces;
using Rawenv.Models;

namespace Rawenv.ViewModels;

public partial class SettingsViewModel : ObservableObject
{
    private readonly IDataRepository _repository;

    [ObservableProperty] private int _selectedPageIndex;
    [ObservableProperty] private AppSettings _settings = new();
    [ObservableProperty] private string _customEndpoint = "";
    [ObservableProperty] private string _customApiKey = "";
    [ObservableProperty] private string _selectedProvider = "Auto (Groq → Cerebras → CF)";
    [ObservableProperty] private string _selectedAutonomy = "suggest-only";

    public ObservableCollection<string> Providers { get; } = new();
    public ObservableCollection<string> AutonomyLevels { get; } = new();
    public List<string> SettingsPages { get; } = ["General", "Services", "Runtimes", "Network", "Cells", "Deploy", "AI", "Theme", "About"];

    public SettingsViewModel(IDataRepository repository)
    {
        _repository = repository;
    }

    [RelayCommand]
    public async Task LoadAsync()
    {
        Settings = await _repository.FetchSettingsAsync();
        Providers.Clear();
        foreach (var p in Settings.AI.Providers) Providers.Add(p);
        AutonomyLevels.Clear();
        foreach (var l in Settings.AI.AutonomyLevels) AutonomyLevels.Add(l);
        SelectedProvider = Settings.AI.Provider;
        SelectedAutonomy = Settings.AI.DefaultAutonomy;
        CustomEndpoint = Settings.AI.CustomEndpoint;
        CustomApiKey = Settings.AI.CustomApiKey;
    }
}
