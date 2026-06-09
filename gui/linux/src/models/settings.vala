public class Rawenv.Settings : Object {
    public string store_location { get; set; default = "~/.rawenv/store/"; }
    public bool auto_start_services { get; set; default = true; }
    public bool auto_detect_projects { get; set; default = true; }
    public bool launch_at_login { get; set; default = false; }
    public bool file_watcher { get; set; default = true; }
    public string local_domain { get; set; default = ".test"; }
    public bool auto_tls { get; set; default = true; }
    public int proxy_port { get; set; default = 80; }
    public string tunnel_provider { get; set; default = "bore (built-in)"; }
    public bool cells_enabled { get; set; default = true; }
    public string default_memory_limit { get; set; default = "256MB"; }
    public string deploy_provider { get; set; default = "Hetzner"; }
    public string ai_provider { get; set; default = "Auto (Groq → Cerebras → CF)"; }
    public string ai_api_key { get; set; default = ""; }
    public string ai_custom_endpoint { get; set; default = ""; }
    public bool proactive_suggestions { get; set; default = true; }
    public bool auto_apply_safe { get; set; default = false; }
    public string default_autonomy { get; set; default = "suggest-only"; }
    public string theme_mode { get; set; default = "dark"; }
    public string accent_color { get; set; default = "#6366f1"; }
    public int font_size { get; set; default = 13; }
}
