public class Rawenv.AiChatView : Adw.Bin {
    private AiChatViewModel vm;
    private Gtk.Box messages_box;
    private Gtk.Entry input_entry;

    public AiChatView (AiChatViewModel vm) {
        this.vm = vm;
        vm.load ();
        build_ui ();
    }

    private void build_ui () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        box.set_margin_start (16);
        box.set_margin_end (16);
        box.set_margin_top (16);

        // Header with provider selector
        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        var title = new Gtk.Label ("AI Chat");
        title.add_css_class ("title-1");
        title.set_halign (Gtk.Align.START);
        title.set_hexpand (true);
        header.append (title);

        var provider_combo = new Gtk.DropDown.from_strings ({
            "Auto (Groq → Cerebras → CF)",
            "Groq (Llama 3.3 70B)",
            "Cerebras (Qwen3 235B)",
            "Cloudflare Workers AI",
            "Ollama (local)"
        });
        provider_combo.set_name ("ai_provider_selector");
        header.append (provider_combo);
        box.append (header);

        // Messages area
        messages_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        messages_box.set_name ("ai_messages_list");
        messages_box.set_margin_top (8);
        refresh_messages ();

        var scroll = new Gtk.ScrolledWindow ();
        scroll.set_child (messages_box);
        scroll.set_vexpand (true);
        box.append (scroll);

        // Input area
        var input_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        input_box.set_margin_bottom (16);
        input_box.set_margin_top (8);

        input_entry = new Gtk.Entry ();
        input_entry.set_hexpand (true);
        input_entry.set_placeholder_text ("Ask rawenv AI…");
        input_entry.set_name ("ai_chat_input");
        input_entry.activate.connect (send_message);

        var send_btn = new Gtk.Button.with_label ("Send");
        send_btn.set_name ("ai_send_button");
        send_btn.add_css_class ("suggested-action");
        send_btn.clicked.connect (send_message);

        input_box.append (input_entry);
        input_box.append (send_btn);
        box.append (input_box);

        this.set_child (box);
    }

    private void send_message () {
        var text = input_entry.get_text ();
        if (text.length > 0) {
            vm.send (text);
            input_entry.set_text ("");
            refresh_messages ();
        }
    }

    private void refresh_messages () {
        var child = messages_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            messages_box.remove (child);
            child = next;
        }
        for (uint i = 0; i < vm.messages.length; i++) {
            var m = vm.messages[i];
            var bubble = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            bool is_user = m.role == "user";

            var lbl = new Gtk.Label (m.text);
            lbl.set_wrap (true);
            lbl.set_max_width_chars (60);
            lbl.set_halign (Gtk.Align.START);
            lbl.set_margin_start (12);
            lbl.set_margin_end (12);
            lbl.set_margin_top (8);
            lbl.set_margin_bottom (8);

            bubble.append (lbl);
            bubble.add_css_class (is_user ? "message-bubble-user" : "message-bubble-assistant");
            bubble.set_halign (is_user ? Gtk.Align.END : Gtk.Align.START);
            bubble.set_margin_start (is_user ? 64 : 0);
            bubble.set_margin_end (is_user ? 0 : 64);
            bubble.set_name ("ai_message_%u".printf (i));

            messages_box.append (bubble);
        }
    }
}
