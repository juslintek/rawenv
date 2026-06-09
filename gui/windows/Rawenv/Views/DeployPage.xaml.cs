using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Rawenv.Interfaces;
using Rawenv.Services;

namespace Rawenv.Views;

public sealed partial class DeployPage : Page
{
    private readonly MockDeployEngine _engine;
    private readonly IDataRepository _repository;

    public DeployPage()
    {
        _engine = App.Services.GetRequiredService<MockDeployEngine>();
        _repository = App.Services.GetRequiredService<IDataRepository>();
        InitializeComponent();
        DeployLogList.ItemsSource = _engine.Logs;
        _engine.PropertyChanged += Engine_PropertyChanged;
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        var config = await _repository.FetchDeployConfigAsync();
        TerraformText.Text = config.Terraform;
        AnsibleText.Text = config.Ansible;
        ContainerfileText.Text = config.Containerfile;
    }

    private void Engine_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(MockDeployEngine.Progress):
                DeployProgress.Value = _engine.Progress;
                break;
            case nameof(MockDeployEngine.HasError):
                AIFixPanel.Visibility = _engine.HasError ? Visibility.Visible : Visibility.Collapsed;
                break;
            case nameof(MockDeployEngine.IsRunning):
                DeployButton.IsEnabled = !_engine.IsRunning;
                break;
        }
    }

    private void Deploy_Click(object sender, RoutedEventArgs e) => _engine.StartDeploy();
    private void AIFix_Click(object sender, RoutedEventArgs e) => _engine.ApplyAIFix();
}
