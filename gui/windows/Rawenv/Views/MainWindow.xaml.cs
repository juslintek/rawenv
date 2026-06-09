using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Rawenv.Views;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "rawenv";
        NavView.SelectedItem = NavView.MenuItems[0];
        ContentFrame.Navigate(typeof(DashboardPage));
    }

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is NavigationViewItem item && item.Tag is string tag)
        {
            var pageType = tag switch
            {
                "Dashboard" => typeof(DashboardPage),
                "AIChat" => typeof(AIChatPage),
                "Connections" => typeof(ConnectionsPage),
                "Deploy" => typeof(DeployPage),
                "Tunnel" => typeof(TunnelPage),
                "Projects" => typeof(ProjectsPage),
                "Installer" => typeof(InstallerPage),
                "Uninstall" => typeof(UninstallPage),
                "Settings" => typeof(SettingsPage),
                _ => typeof(DashboardPage)
            };
            ContentFrame.Navigate(pageType);
        }
    }
}
