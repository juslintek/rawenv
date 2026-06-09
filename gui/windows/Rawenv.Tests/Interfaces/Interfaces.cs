using Rawenv.Models;

namespace Rawenv.Interfaces;

public interface IDataRepository
{
    Task<IReadOnlyList<Service>> FetchServicesAsync();
    Task<IReadOnlyList<LogEntry>> FetchLogsAsync();
    Task<IReadOnlyList<Connection>> FetchConnectionsAsync();
    Task<IReadOnlyList<Project>> FetchProjectsAsync();
    Task<IReadOnlyList<AIMessage>> FetchAIMessagesAsync();
    Task<AppSettings> FetchSettingsAsync();
    Task<DeployConfig> FetchDeployConfigAsync();
    Task<InstallerConfig> FetchInstallerConfigAsync();
}

public interface INavigationService
{
    void NavigateTo(string destination);
    void GoBack();
    event Action<string>? Navigated;
}

public interface IAIProvider
{
    Task<string> SendAsync(string prompt);
    string AutonomyLevel { get; set; }
}
