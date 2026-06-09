using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Rawenv.Services;

namespace Rawenv.ViewModels;

public partial class InstallerViewModel : ObservableObject
{
    public MockInstallerEngine Engine { get; }

    public InstallerViewModel(MockInstallerEngine engine)
    {
        Engine = engine;
    }

    [RelayCommand]
    public void Install() => Engine.StartInstall();

    [RelayCommand]
    public void Reset() => Engine.Reset();
}
