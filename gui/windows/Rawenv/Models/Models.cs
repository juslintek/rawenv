namespace Rawenv.Models;

public record Service(string Name, int Port, string Version, int? Pid, string? Cpu, string? Mem, string? Uptime, string Status, string Icon);
public record LogEntry(string Time, string Msg, string Level);
public record AIMessage(string Role, string Text);
public record Connection(string EnvVar, string Original, string Local, string? Proxy, string? Alternative, string Mode, string Badge);
public record Project(string Name, string Path, List<string> Stack, string Deps);

public class AppSettings
{
    public GeneralSettings General { get; set; } = new();
    public NetworkSettings Network { get; set; } = new();
    public CellsSettings Cells { get; set; } = new();
    public DeploySettings Deploy { get; set; } = new();
    public AISettings AI { get; set; } = new();
    public ThemeSettings Theme { get; set; } = new();
}

public class GeneralSettings
{
    public string StoreLocation { get; set; } = "~/.rawenv/store/";
    public bool AutoStartServices { get; set; } = true;
    public bool AutoDetectProjects { get; set; } = true;
    public bool LaunchAtLogin { get; set; }
    public bool FileWatcher { get; set; } = true;
    public List<string> ScanPaths { get; set; } = new();
}

public class NetworkSettings
{
    public string LocalDomain { get; set; } = ".test";
    public bool AutoTls { get; set; } = true;
    public int ProxyPort { get; set; } = 80;
    public string TunnelProvider { get; set; } = "bore (built-in)";
    public string RelayServer { get; set; } = "bore.pub";
}

public class CellsSettings
{
    public bool EnableByDefault { get; set; } = true;
    public string DefaultMemoryLimit { get; set; } = "256MB";
    public string DefaultCpuLimit { get; set; } = "1";
    public bool NetworkIsolation { get; set; } = true;
}

public class DeploySettings
{
    public string Provider { get; set; } = "Hetzner";
    public string SshKey { get; set; } = "~/.ssh/id_ed25519.pub";
    public string TerraformPath { get; set; } = "terraform";
    public string AnsiblePath { get; set; } = "ansible-playbook";
    public bool AutoGenerate { get; set; }
    public string ContainerRuntime { get; set; } = "Podman";
    public string Registry { get; set; } = "ghcr.io/rawenv";
}

public class AISettings
{
    public string Provider { get; set; } = "Auto (Groq → Cerebras → CF)";
    public List<string> Providers { get; set; } = new();
    public string ApiKey { get; set; } = "";
    public string OllamaEndpoint { get; set; } = "http://localhost:11434";
    public bool ProactiveSuggestions { get; set; } = true;
    public bool AutoApplySafeFixes { get; set; }
    public bool IncludeLogsInContext { get; set; } = true;
    public int MaxContextSize { get; set; } = 4096;
    public List<string> AutonomyLevels { get; set; } = new();
    public string DefaultAutonomy { get; set; } = "suggest-only";
    public string CustomEndpoint { get; set; } = "";
    public string CustomApiKey { get; set; } = "";
}

public class ThemeSettings
{
    public string Mode { get; set; } = "dark";
    public string AccentColor { get; set; } = "#6366f1";
    public string SuccessColor { get; set; } = "#34d399";
    public string ErrorColor { get; set; } = "#f87171";
    public string WarningColor { get; set; } = "#fbbf24";
    public int BorderRadius { get; set; } = 8;
    public int FontSize { get; set; } = 13;
    public int SidebarWidth { get; set; } = 240;
}

public class DeployConfig
{
    public string Terraform { get; set; } = "";
    public string Ansible { get; set; } = "";
    public string Containerfile { get; set; } = "";
}

public class InstallerConfig
{
    public List<string> Steps { get; set; } = new();
    public Dictionary<string, PlatformInfo> Platforms { get; set; } = new();
}

public class PlatformInfo
{
    public string Icon { get; set; } = "";
    public string Name { get; set; } = "";
    public string Detail { get; set; } = "";
    public string ServiceManager { get; set; } = "";
    public string Isolation { get; set; } = "";
    public string Dns { get; set; } = "";
}
