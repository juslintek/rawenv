using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Dispatching;

namespace Rawenv.Services;

public partial class MockInstallerEngine : ObservableObject
{
    public enum InstallerState { Welcome, Installing, Done }

    [ObservableProperty] private InstallerState _state = InstallerState.Welcome;
    [ObservableProperty] private int _currentStep;
    [ObservableProperty] private double _progress;

    public string[] Steps { get; } =
    [
        "Downloading binary…",
        "Installing rawenv…",
        "Registering service manager…",
        "Configuring isolation…",
        "Setting up DNS…",
        "Adding to PATH…",
    ];

    private DispatcherQueueTimer? _timer;
    private readonly DispatcherQueue _dispatcher;

    public MockInstallerEngine()
    {
        _dispatcher = DispatcherQueue.GetForCurrentThread();
    }

    public void StartInstall()
    {
        State = InstallerState.Installing;
        CurrentStep = 0;
        Progress = 0;

        _timer = _dispatcher.CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(350);
        _timer.Tick += OnTick;
        _timer.Start();
    }

    private void OnTick(DispatcherQueueTimer sender, object args)
    {
        CurrentStep++;
        Progress = (double)CurrentStep / Steps.Length;

        if (CurrentStep >= Steps.Length)
        {
            _timer?.Stop();
            _timer = null;
            State = InstallerState.Done;
        }
    }

    public void Reset()
    {
        _timer?.Stop();
        _timer = null;
        State = InstallerState.Welcome;
        CurrentStep = 0;
        Progress = 0;
    }
}
