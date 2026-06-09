public class Rawenv.AiChatViewModel : Object {
    private DataRepository repo;
    private AiProvider provider;
    public GenericArray<AiMessage> messages { get; owned set; }

    public AiChatViewModel (DataRepository repo, AiProvider provider) {
        this.repo = repo;
        this.provider = provider;
        this.messages = new GenericArray<AiMessage> ();
    }

    public void load () {
        messages = repo.get_ai_messages ();
        notify_property ("messages");
    }

    public void send (string text) {
        var user_msg = new AiMessage ();
        user_msg.role = "user";
        user_msg.text = text;
        messages.add (user_msg);

        var response = provider.send_message (text);
        var ai_msg = new AiMessage ();
        ai_msg.role = "assistant";
        ai_msg.text = response;
        messages.add (ai_msg);
        notify_property ("messages");
    }
}
