public interface Rawenv.AiProvider : Object {
    public abstract string send_message (string prompt);
    public abstract string autonomy_level { get; set; }
}
