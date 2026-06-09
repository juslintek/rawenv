public class Rawenv.SettingsViewModel : Object {
    private DataRepository repo;
    public Settings settings { get; owned set; }
    public int selected_page { get; set; default = 0; }

    public string[] ai_providers = {
        "Auto (Groq → Cerebras → CF)",
        "Groq (Llama 3.3 70B)",
        "Cerebras (Qwen3 235B)",
        "Cloudflare Workers AI",
        "Google Gemini",
        "Mistral AI",
        "Ollama (local)",
        "Custom OpenAI-compatible"
    };

    public string[] autonomy_levels = {
        "suggest-only",
        "auto-apply-safe",
        "confirm-dangerous",
        "full-autonomous"
    };

    public SettingsViewModel (DataRepository repo) {
        this.repo = repo;
        this.settings = new Settings ();
    }

    public void load () {
        settings = repo.get_settings ();
        notify_property ("settings");
    }

    public bool is_byom () {
        return settings.ai_provider == "Custom OpenAI-compatible";
    }
}
