using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Dispatching;

namespace Rawenv.Services;

public partial class MockDeployEngine : ObservableObject
{
    public record DeployLogEntry(string Text, bool IsError);

    [ObservableProperty] private double _progress;
    [ObservableProperty] private bool _isRunning;
    [ObservableProperty] private bool _hasError;
    [ObservableProperty] private bool _isComplete;

    public ObservableCollection<DeployLogEntry> Logs { get; } = new();

    private static readonly (string text, bool isError)[] Steps =
    [
        ("$ terraform init\nInitializing provider plugins...\nTerraform has been successfully initialized!", false),
        ("$ terraform plan\nPlan: 3 to add, 0 to change, 0 to destroy.", false),
        ("$ terraform apply -auto-approve\nhcloud_server.myapp: Creating...\nhcloud_server.myapp: Creation complete after 12s [id=48291]", false),
        ("$ ssh root@116.203.xx.xx\nConnected to myapp-prod (Debian 13)", false),
        ("$ curl -fsSL rawenv.sh/install | sh\nrawenv v0.1.0 installed to /usr/local/bin/rawenv", false),
        ("$ rawenv init --from-toml rawenv.toml\nConfiguration loaded: 5 services", false),
        ("$ rawenv up\n✓ PostgreSQL started on :5432\n✓ Meilisearch started on :7700\n✗ Redis failed: port 6379 already in use (conflict with system redis-server)", true),
    ];

    private DispatcherQueueTimer? _timer;
    private readonly DispatcherQueue _dispatcher;
    private int _stepIndex;

    public MockDeployEngine()
    {
        _dispatcher = DispatcherQueue.GetForCurrentThread();
    }

    public void StartDeploy()
    {
        Logs.Clear();
        Progress = 0;
        IsRunning = true;
        HasError = false;
        IsComplete = false;
        _stepIndex = 0;

        _timer = _dispatcher.CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(500);
        _timer.Tick += OnTick;
        _timer.Start();
    }

    private void OnTick(DispatcherQueueTimer sender, object args)
    {
        if (_stepIndex >= Steps.Length)
        {
            _timer?.Stop();
            _timer = null;
            IsRunning = false;
            IsComplete = true;
            return;
        }

        var (text, isError) = Steps[_stepIndex];
        Logs.Add(new DeployLogEntry(text, isError));
        _stepIndex++;
        Progress = (double)_stepIndex / Steps.Length;

        if (isError)
        {
            _timer?.Stop();
            _timer = null;
            HasError = true;
            IsRunning = false;
        }
    }

    public void ApplyAIFix()
    {
        HasError = false;
        IsRunning = true;

        var fixTimer = _dispatcher.CreateTimer();
        fixTimer.Interval = TimeSpan.FromMilliseconds(700);
        fixTimer.IsRepeating = false;
        fixTimer.Tick += (_, _) =>
        {
            Logs.Add(new DeployLogEntry("🤖 AI Fix: Stopping system redis-server, binding rawenv Redis to :6379\n✓ Redis started on :6379", false));
            Progress = 1.0;
            IsRunning = false;
            IsComplete = true;
        };
        fixTimer.Start();
    }
}
