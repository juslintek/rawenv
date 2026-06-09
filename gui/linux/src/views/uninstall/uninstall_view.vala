public class Rawenv.UninstallView : Adw.Bin {
    public UninstallView () {
        build_ui ();
    }

    private void build_ui () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
        box.set_margin_start (24);
        box.set_margin_end (24);
        box.set_margin_top (24);

        var title = new Gtk.Label ("Uninstall rawenv");
        title.add_css_class ("title-1");
        title.set_halign (Gtk.Align.START);
        box.append (title);

        var warning_lbl = new Gtk.Label ("This will remove rawenv and all managed runtimes from ~/.rawenv/");
        warning_lbl.set_wrap (true);
        warning_lbl.set_name ("uninstall_warning");
        box.append (warning_lbl);

        var keep_data = new Gtk.CheckButton.with_label ("Keep project data (rawenv.toml files)");
        keep_data.set_name ("uninstall_keep_data");
        box.append (keep_data);

        var remove_config = new Gtk.CheckButton.with_label ("Remove shell configuration changes");
        remove_config.set_name ("uninstall_remove_config");
        box.append (remove_config);

        var uninstall_btn = new Gtk.Button.with_label ("Uninstall");
        uninstall_btn.set_name ("uninstall_button");
        uninstall_btn.add_css_class ("destructive-action");
        box.append (uninstall_btn);

        this.set_child (box);
    }
}
