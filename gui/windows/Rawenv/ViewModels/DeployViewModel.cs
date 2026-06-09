using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Rawenv.Interfaces;
using Rawenv.Models;
using Rawenv.Services;

namespace Rawenv.ViewModels;

public partial class DeployViewModel : ObservableObject
{
    private readonly IDataRepository _repository;
    public MockDeployEngine Engine { get; }

    [ObservableProperty] private string _terraform = "";
    [ObservableProperty] private string _ansible = "";
    [ObservableProperty] private string _containerfile = "";

    public DeployViewModel(IDataRepository repository, MockDeployEngine engine)
    {
        _repository = repository;
        Engine = engine;
    }

    [RelayCommand]
    public async Task LoadAsync()
    {
        var config = await _repository.FetchDeployConfigAsync();
        Terraform = config.Terraform;
        Ansible = config.Ansible;
        Containerfile = config.Containerfile;
    }
}
