using System.Text.Json;
using System.Text.Json.Serialization;
using Rawenv.Interfaces;
using Rawenv.Models;

namespace Rawenv.Services;

public class MockDataRepository : IDataRepository
{
    private JsonElement _root;
    private bool _loaded;
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    private async Task EnsureLoadedAsync()
    {
        if (_loaded) return;
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "mock-data.json");
        var json = await File.ReadAllTextAsync(path);
        _root = JsonDocument.Parse(json).RootElement;
        _loaded = true;
    }

    public async Task<IReadOnlyList<Service>> FetchServicesAsync()
    {
        await EnsureLoadedAsync();
        return JsonSerializer.Deserialize<List<Service>>(_root.GetProperty("services").GetRawText(), JsonOpts) ?? new();
    }

    public async Task<IReadOnlyList<LogEntry>> FetchLogsAsync()
    {
        await EnsureLoadedAsync();
        return JsonSerializer.Deserialize<List<LogEntry>>(_root.GetProperty("logs").GetRawText(), JsonOpts) ?? new();
    }

    public async Task<IReadOnlyList<Connection>> FetchConnectionsAsync()
    {
        await EnsureLoadedAsync();
        return JsonSerializer.Deserialize<List<Connection>>(_root.GetProperty("connections").GetRawText(), JsonOpts) ?? new();
    }

    public async Task<IReadOnlyList<Project>> FetchProjectsAsync()
    {
        await EnsureLoadedAsync();
        return JsonSerializer.Deserialize<List<Project>>(_root.GetProperty("projects").GetRawText(), JsonOpts) ?? new();
    }

    public async Task<IReadOnlyList<AIMessage>> FetchAIMessagesAsync()
    {
        await EnsureLoadedAsync();
        return JsonSerializer.Deserialize<List<AIMessage>>(_root.GetProperty("aiMessages").GetRawText(), JsonOpts) ?? new();
    }

    public async Task<AppSettings> FetchSettingsAsync()
    {
        await EnsureLoadedAsync();
        return JsonSerializer.Deserialize<AppSettings>(_root.GetProperty("settings").GetRawText(), JsonOpts) ?? new();
    }

    public async Task<DeployConfig> FetchDeployConfigAsync()
    {
        await EnsureLoadedAsync();
        return JsonSerializer.Deserialize<DeployConfig>(_root.GetProperty("deploy").GetRawText(), JsonOpts) ?? new();
    }

    public async Task<InstallerConfig> FetchInstallerConfigAsync()
    {
        await EnsureLoadedAsync();
        return JsonSerializer.Deserialize<InstallerConfig>(_root.GetProperty("installer").GetRawText(), JsonOpts) ?? new();
    }
}
