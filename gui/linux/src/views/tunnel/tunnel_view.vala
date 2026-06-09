public class Rawenv.TunnelView : Adw.Bin {
    public TunnelView () {
        build_ui ();
    }

    private void build_ui () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        box.set_margin_start (16);
        box.set_margin_end (16);
        box.set_margin_top (16);

        var title = new Gtk.Label ("Tunnel");
        title.add_css_class ("title-1");
        title.set_halign (Gtk.Align.START);
        box.append (title);

        var desc = new Gtk.Label ("Expose local services via SSH tunnel");
        desc.set_halign (Gtk.Align.START);
        box.append (desc);

        var port_entry = new Gtk.Entry ();
        port_entry.set_placeholder_text ("Port (e.g. 3000)");
        port_entry.set_name ("tunnel_port_input");
        box.append (port_entry);

        var provider_lbl = new Gtk.Label ("Provider: bore (built-in) · Relay: bore.pub");
        provider_lbl.set_halign (Gtk.Align.START);
        provider_lbl.set_name ("tunnel_provider_info");
        box.append (provider_lbl);

        var cmd_lbl = new Gtk.Label ("ssh -R 80:localhost:3000 bore.pub");
        cmd_lbl.set_halign (Gtk.Align.START);
        cmd_lbl.set_selectable (true);
        cmd_lbl.set_name ("tunnel_command");
        cmd_lbl.add_css_class ("monospace");
        box.append (cmd_lbl);

        var start_btn = new Gtk.Button.with_label ("Start Tunnel");
        start_btn.set_name ("tunnel_start_button");
        start_btn.add_css_class ("suggested-action");
        box.append (start_btn);

        this.set_child (box);
    }
}
