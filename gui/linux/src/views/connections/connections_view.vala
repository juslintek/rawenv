public class Rawenv.ConnectionsView : Adw.Bin {
    private ConnectionsViewModel vm;
    private Gtk.Box cards_box;

    public ConnectionsView (ConnectionsViewModel vm) {
        this.vm = vm;
        vm.load ();
        build_ui ();
    }

    private void build_ui () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.set_margin_start (16);
        box.set_margin_end (16);
        box.set_margin_top (16);

        var title = new Gtk.Label ("Connections");
        title.add_css_class ("title-1");
        title.set_halign (Gtk.Align.START);
        box.append (title);

        var subtitle = new Gtk.Label ("Service connection strings with mode switching");
        subtitle.add_css_class ("dim-label");
        subtitle.set_halign (Gtk.Align.START);
        box.append (subtitle);

        cards_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
        cards_box.set_name ("connections_list");
        build_cards ();

        var scroll = new Gtk.ScrolledWindow ();
        scroll.set_child (cards_box);
        scroll.set_vexpand (true);
        box.append (scroll);

        this.set_child (box);
    }

    private void build_cards () {
        for (uint i = 0; i < vm.connections.length; i++) {
            var c = vm.connections[i];
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            card.add_css_class ("connection-card");
            card.set_name ("connection_%s".printf (c.env_var));

            // Header row: env var + badge
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var env_lbl = new Gtk.Label (c.env_var);
            env_lbl.add_css_class ("heading");
            env_lbl.set_hexpand (true);
            env_lbl.set_halign (Gtk.Align.START);
            header.append (env_lbl);

            var badge = new Gtk.Label (c.badge);
            badge.add_css_class ("caption");
            string badge_class = "mode-badge-local";
            if (c.mode == "proxy") badge_class = "mode-badge-proxy";
            if (c.mode == "tunnel") badge_class = "mode-badge-tunnel";
            badge.add_css_class (badge_class);
            header.append (badge);
            card.append (header);

            // Connection values
            var values_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            var orig_lbl = new Gtk.Label ("Original: %s".printf (c.original));
            orig_lbl.add_css_class ("monospace");
            orig_lbl.add_css_class ("dim-label");
            orig_lbl.set_halign (Gtk.Align.START);
            values_box.append (orig_lbl);

            if (c.local.length > 0) {
                var local_lbl = new Gtk.Label ("Local: %s".printf (c.local));
                local_lbl.add_css_class ("monospace");
                local_lbl.set_halign (Gtk.Align.START);
                values_box.append (local_lbl);
            }
            if (c.proxy.length > 0) {
                var proxy_lbl = new Gtk.Label ("Proxy: %s".printf (c.proxy));
                proxy_lbl.add_css_class ("monospace");
                proxy_lbl.add_css_class ("dim-label");
                proxy_lbl.set_halign (Gtk.Align.START);
                values_box.append (proxy_lbl);
            }
            card.append (values_box);

            // Mode toggle buttons
            var mode_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            mode_row.set_margin_top (6);
            string[] modes = { "local", "proxy", "tunnel" };
            foreach (var m in modes) {
                var btn = new Gtk.ToggleButton.with_label (m);
                btn.set_active (c.mode == m);
                btn.add_css_class ("flat");
                if (c.mode == m) btn.add_css_class ("suggested-action");
                mode_row.append (btn);
            }
            card.append (mode_row);

            cards_box.append (card);
        }
    }
}
