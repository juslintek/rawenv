using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Rawenv.ViewModels;
using Windows.System;

namespace Rawenv.Views;

public sealed partial class AIChatPage : Page
{
    public AIChatViewModel ViewModel { get; }

    public AIChatPage()
    {
        ViewModel = App.Services.GetRequiredService<AIChatViewModel>();
        InitializeComponent();
        ViewModel.Messages.CollectionChanged += (_, _) => ScrollToBottom();
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e) => await ViewModel.LoadAsync();

    private void Input_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter && !string.IsNullOrWhiteSpace(ViewModel.InputText))
        {
            ViewModel.SendCommand.Execute(null);
            e.Handled = true;
        }
    }

    private void ScrollToBottom()
    {
        if (ViewModel.Messages.Count > 0)
            MessagesList.ScrollIntoView(ViewModel.Messages[^1]);
    }
}
