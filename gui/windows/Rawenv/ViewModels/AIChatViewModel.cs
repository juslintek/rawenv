using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Rawenv.Interfaces;
using Rawenv.Models;

namespace Rawenv.ViewModels;

public partial class AIChatViewModel : ObservableObject
{
    private readonly IDataRepository _repository;
    private readonly IAIProvider _aiProvider;

    public ObservableCollection<AIMessage> Messages { get; } = new();

    [ObservableProperty] private string _inputText = "";
    [ObservableProperty] private string _selectedProvider = "Auto (Groq → Cerebras → CF)";
    [ObservableProperty] private bool _isSending;

    public AIChatViewModel(IDataRepository repository, IAIProvider aiProvider)
    {
        _repository = repository;
        _aiProvider = aiProvider;
    }

    [RelayCommand]
    public async Task LoadAsync()
    {
        var messages = await _repository.FetchAIMessagesAsync();
        Messages.Clear();
        foreach (var m in messages) Messages.Add(m);
    }

    [RelayCommand]
    public async Task SendAsync()
    {
        if (string.IsNullOrWhiteSpace(InputText)) return;
        var userMsg = InputText;
        Messages.Add(new AIMessage("user", userMsg));
        InputText = "";
        IsSending = true;
        var response = await _aiProvider.SendAsync(userMsg);
        Messages.Add(new AIMessage("assistant", response));
        IsSending = false;
    }
}
