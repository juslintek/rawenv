using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Dispatching;
using Rawenv.Interfaces;
using Rawenv.Models;

namespace Rawenv.Services;

public partial class MockServiceManager : ObservableObject
{
    private readonly IDataRepository _repository;
    private readonly DispatcherQueue _dispatcher;
    public ObservableCollection<Service> Services { get; } = new();

    [ObservableProperty] private int _runningCount;
    [ObservableProperty] private string _totalCpu = "0%";
    [ObservableProperty] private string _totalMem = "0 MB";

    public MockServiceManager(IDataRepository repository)
    {
        _repository = repository;
        _dispatcher = DispatcherQueue.GetForCurrentThread();
        _ = LoadAsync();
    }

    private async Task LoadAsync()
    {
        var services = await _repository.FetchServicesAsync();
        Services.Clear();
        foreach (var s in services) Services.Add(s);
        UpdateStats();
    }

    public void StartService(string name)
    {
        var idx = IndexOf(name);
        if (idx < 0) return;
        var s = Services[idx];
        Services[idx] = s with { Pid = Random.Shared.Next(10000, 65000), Cpu = "0.1%", Mem = "8MB", Uptime = "0s", Status = "running" };
        UpdateStats();
    }

    public void StopService(string name)
    {
        var idx = IndexOf(name);
        if (idx < 0) return;
        var s = Services[idx];
        Services[idx] = s with { Pid = null, Cpu = null, Mem = null, Uptime = null, Status = "stopped" };
        UpdateStats();
    }

    public void RestartService(string name)
    {
        StopService(name);
        var timer = _dispatcher.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(300);
        timer.IsRepeating = false;
        timer.Tick += (_, _) => StartService(name);
        timer.Start();
    }

    public void StartAll()
    {
        for (int i = 0; i < Services.Count; i++)
            if (Services[i].Status != "running") StartService(Services[i].Name);
    }

    public void StopAll()
    {
        for (int i = 0; i < Services.Count; i++)
            if (Services[i].Status == "running") StopService(Services[i].Name);
    }

    private void UpdateStats()
    {
        RunningCount = Services.Count(s => s.Status == "running");
        var cpuTotal = Services.Where(s => s.Cpu != null).Sum(s => double.TryParse(s.Cpu!.TrimEnd('%'), out var v) ? v : 0);
        TotalCpu = $"{cpuTotal:F1}%";
        var memTotal = Services.Where(s => s.Mem != null).Sum(s => double.TryParse(s.Mem!.Replace("MB", "").Trim(), out var v) ? v : 0);
        TotalMem = $"{memTotal:F0} MB";
    }

    private int IndexOf(string name) => Enumerable.Range(0, Services.Count).FirstOrDefault(i => Services[i].Name == name, -1);
}
