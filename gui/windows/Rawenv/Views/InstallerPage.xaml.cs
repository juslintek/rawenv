using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Rawenv.Interfaces;
using Rawenv.Services;

namespace Rawenv.Views;

public sealed partial class InstallerPage : Page
{
    private readonly MockInstallerEngine _engine;
    private static readonly SolidColorBrush ActiveDot = new(Microsoft.UI.ColorHelper.FromArgb(255, 0x63, 0x66, 0xf1));
    private static readonly SolidColorBrush InactiveDot = new(Microsoft.UI.ColorHelper.FromArgb(255, 0x1e, 0x1e, 0x2a));
    private static readonly SolidColorBrush DoneDot = new(Microsoft.UI.ColorHelper.FromArgb(255, 0x34, 0xd3, 0x99));

    public InstallerPage()
    {
        _engine = App.Services.GetRequiredService<MockInstallerEngine>();
        InitializeComponent();
        _engine.PropertyChanged += Engine_PropertyChanged;
        UpdateUI();
    }

    private void Engine_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        UpdateUI();
    }

    private void UpdateUI()
    {
        switch (_engine.State)
        {
            case MockInstallerEngine.InstallerState.Welcome:
                WelcomePanel.Visibility = Visibility.Visible;
                InstallingPanel.Visibility = Visibility.Collapsed;
                DonePanel.Visibility = Visibility.Collapsed;
                Step1Dot.Fill = ActiveDot;
                Step2Dot.Fill = InactiveDot;
                Step3Dot.Fill = InactiveDot;
                break;
            case MockInstallerEngine.InstallerState.Installing:
                WelcomePanel.Visibility = Visibility.Collapsed;
                InstallingPanel.Visibility = Visibility.Visible;
                DonePanel.Visibility = Visibility.Collapsed;
                InstallProgress.Value = _engine.Progress;
                StepLabel.Text = _engine.CurrentStep < _engine.Steps.Length
                    ? _engine.Steps[_engine.CurrentStep] : "Finishing…";
                Step1Dot.Fill = DoneDot;
                Step2Dot.Fill = ActiveDot;
                Step3Dot.Fill = InactiveDot;
                break;
            case MockInstallerEngine.InstallerState.Done:
                WelcomePanel.Visibility = Visibility.Collapsed;
                InstallingPanel.Visibility = Visibility.Collapsed;
                DonePanel.Visibility = Visibility.Visible;
                Step1Dot.Fill = DoneDot;
                Step2Dot.Fill = DoneDot;
                Step3Dot.Fill = DoneDot;
                break;
        }
    }

    private void Install_Click(object sender, RoutedEventArgs e) => _engine.StartInstall();

    private void GoToDashboard_Click(object sender, RoutedEventArgs e)
    {
        var nav = App.Services.GetRequiredService<INavigationService>();
        nav.NavigateTo("Dashboard");
    }
}
