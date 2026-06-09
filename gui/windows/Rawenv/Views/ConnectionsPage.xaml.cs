using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Rawenv.ViewModels;

namespace Rawenv.Views;

public sealed partial class ConnectionsPage : Page
{
    public ConnectionsViewModel ViewModel { get; }

    public ConnectionsPage()
    {
        ViewModel = App.Services.GetRequiredService<ConnectionsViewModel>();
        InitializeComponent();
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e) => await ViewModel.LoadAsync();

    private void ModeSelector_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (ModeSelector.SelectedItem is ComboBoxItem item)
        {
            ModeDescription.Text = item.Content?.ToString() switch
            {
                "Local" => "Local mode: Services connect directly via localhost ports.",
                "Proxy" => "Proxy mode: Traffic routed through Caddy reverse proxy with TLS.",
                "Tunnel" => "Tunnel mode: Exposed via SSH tunnel for remote access.",
                _ => ""
            };
        }
    }
}
