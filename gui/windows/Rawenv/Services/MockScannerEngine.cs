using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Dispatching;
using Rawenv.Models;

namespace Rawenv.Services;

public partial class MockScannerEngine : ObservableObject
{
    public enum ScanState { Idle, Scanning, Done }

    [ObservableProperty] private ScanState _state = ScanState.Idle;
    [ObservableProperty] private string _currentPath = "";
    [ObservableProperty] private double _progress;

    public ObservableCollection<Project> DiscoveredProjects { get; } = new();

    private static readonly (string path, Project project)[] MockPaths =
    [
        ("~/Projects/GOTAS/utilio", new Project("utilio", "~/Projects/GOTAS/utilio", ["Node.js", "Qwik", "PostgreSQL", "Redis", "Meilisearch", "SQL Server"], "14 deps")),
        ("~/Projects/GOTAS/vialietuva-legacy", new Project("vialietuva-legacy", "~/Projects/GOTAS/vialietuva-legacy", ["PHP", "Laravel", "MySQL", "Redis"], "8 deps")),
        ("~/Projects/rawenv", new Project("rawenv", "~/Projects/rawenv", ["Zig"], "1 dep")),
        ("~/Projects/mcp-for-page-builders", new Project("mcp-for-page-builders", "~/Projects/mcp-for-page-builders", ["Rust", "Cargo"], "2 deps")),
        ("~/Projects/my-saas", new Project("my-saas", "~/Projects/my-saas", ["Node.js", "Next.js", "PostgreSQL", "Redis", "S3"], "10 deps")),
        ("~/Projects/blog", new Project("blog", "~/Projects/blog", ["Ruby", "Jekyll"], "3 deps")),
        ("~/Projects/data-pipeline", new Project("data-pipeline", "~/Projects/data-pipeline", ["Python", "PostgreSQL", "Redis"], "6 deps")),
        ("~/Developer/mobile-app", new Project("mobile-app", "~/Developer/mobile-app", ["Node.js", "React Native", "Firebase"], "5 deps")),
    ];

    private DispatcherQueueTimer? _timer;
    private readonly DispatcherQueue _dispatcher;
    private int _scanIndex;

    public MockScannerEngine()
    {
        _dispatcher = DispatcherQueue.GetForCurrentThread();
    }

    public void StartScan()
    {
        State = ScanState.Scanning;
        DiscoveredProjects.Clear();
        _scanIndex = 0;
        Progress = 0;
        CurrentPath = "";

        _timer = _dispatcher.CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(300);
        _timer.Tick += OnTick;
        _timer.Start();
    }

    private void OnTick(DispatcherQueueTimer sender, object args)
    {
        if (_scanIndex >= MockPaths.Length)
        {
            _timer?.Stop();
            _timer = null;
            State = ScanState.Done;
            CurrentPath = "";
            return;
        }

        var (path, project) = MockPaths[_scanIndex];
        CurrentPath = path;
        DiscoveredProjects.Add(project);
        _scanIndex++;
        Progress = (double)_scanIndex / MockPaths.Length;
    }
}
