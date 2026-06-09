public class Rawenv.MockAiProvider : Object, AiProvider {
    private string _autonomy_level = "suggest-only";
    public string autonomy_level {
        get { return _autonomy_level; }
        set { _autonomy_level = value; }
    }

    public string send_message (string prompt) {
        return "Mock AI response to: %s".printf (prompt);
    }
}
