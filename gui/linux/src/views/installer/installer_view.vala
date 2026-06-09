public class Rawenv.InstallerView : Adw.Bin {
    private InstallerViewModel vm;
    private MockInstallerEngine engine;
    private Gtk.Stack stack;
    private Gtk.ProgressBar progress_bar;
    private Gtk.Box checklist_box;
    private Gtk.Label step_label;

    public InstallerView (InstallerViewModel vm) {
        this.vm = vm;
        this.engine = new MockInstallerEngine ();
        build_ui ();
        connect_signals ();
    }

    private void connect_signals () {
        engine.state_changed.connect (() => {
            switch (engine.state) {
                case MockInstallerEngine.State.WELCOME:
                    stack.set_visible_child_name ("welcome");
                    break;
                case MockInstallerEngine.State.INSTALLING:
                    stack.set_visible_child_name ("installing");
                    break;
                case MockInstallerEngine.State.DONE:
                    stack.set_visible_child_name ("done");
                    break;
            }
        });
        engine.step_changed.connect (() => {
            progress_bar.set_fraction (engine.progress);
            step_label.set_text (engine.current_step < engine.steps.length
                ? engine.steps[engine.current_step]
                : "Complete");
            update_checklist ();
        });
    }

    private void update_checklist () {
        var child = checklist_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            checklist_box.remove (child);
            child = next;
        }
        for (int i = 0; i < engine.steps.length; i++) {
            string icon = i < engine.current_step ? "✓" : (i == engine.current_step ? "⟳" : "○");
            var lbl = new Gtk.Label ("%s  %s".printf (icon, engine.steps[i]));
            lbl.set_halign (Gtk.Align.START);
            lbl.add_css_class (i < engine.current_step ? "success" : "dim-label");
            checklist_box.append (lbl);
        }
    }

    private void build_ui () {
        stack = new Gtk.Stack ();
        stack.set_name ("installer_stack");
        stack.set_transition_type (Gtk.StackTransitionType.SLIDE_LEFT);
        stack.add_named (build_welcome (), "welcome");
        stack.add_named (build_installing (), "installing");
        stack.add_named (build_done (), "done");
        stack.set_visible_child_name ("welcome");
        this.set_child (stack);
    }

    private Gtk.Widget build_welcome () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
        box.set_margin_start (48);
        box.set_margin_end (48);
        box.set_margin_top (48);
        box.set_valign (Gtk.Align.CENTER);
        box.set_vexpand (true);

        var logo = new Gtk.Label ("⚡");
        logo.add_css_class ("title-1");
        logo.set_name ("installer_logo");
        box.append (logo);

        var title = new Gtk.Label ("Welcome to rawenv");
        title.add_css_class ("title-1");
        title.set_name ("installer_title");
        box.append (title);

        var subtitle = new Gtk.Label ("Native dev environments. Zero dependencies.");
        subtitle.add_css_class ("dim-label");
        box.append (subtitle);

        var info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        info_box.set_margin_top (24);
        info_box.add_css_class ("card");
        info_box.set_margin_start (32);
        info_box.set_margin_end (32);

        string[,] items = {
            {"🐧", "Platform", "%s — %s".printf (vm.platform_name, vm.platform_detail)},
            {"⚙️", "Service Manager", vm.service_manager},
            {"🔒", "Isolation", vm.isolation},
            {"🌐", "DNS", "systemd-resolved"}
        };
        for (int i = 0; i < 4; i++) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            row.set_margin_start (16);
            row.set_margin_end (16);
            row.set_margin_top (8);
            row.set_margin_bottom (8);
            var icon = new Gtk.Label (items[i, 0]);
            var label = new Gtk.Label (items[i, 1]);
            label.add_css_class ("dim-label");
            var value = new Gtk.Label (items[i, 2]);
            value.set_hexpand (true);
            value.set_halign (Gtk.Align.END);
            row.append (icon);
            row.append (label);
            row.append (value);
            info_box.append (row);
        }
        box.append (info_box);

        var install_btn = new Gtk.Button.with_label ("Install rawenv");
        install_btn.add_css_class ("suggested-action");
        install_btn.add_css_class ("pill");
        install_btn.set_name ("installer_install_button");
        install_btn.set_halign (Gtk.Align.CENTER);
        install_btn.set_margin_top (24);
        install_btn.clicked.connect (() => engine.start_install ());
        box.append (install_btn);

        return box;
    }

    private Gtk.Widget build_installing () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
        box.set_margin_start (48);
        box.set_margin_end (48);
        box.set_margin_top (48);
        box.set_valign (Gtk.Align.CENTER);
        box.set_vexpand (true);

        var title = new Gtk.Label ("Installing…");
        title.add_css_class ("title-2");
        box.append (title);

        step_label = new Gtk.Label ("Downloading binary…");
        step_label.add_css_class ("dim-label");
        step_label.set_name ("installer_step_label");
        box.append (step_label);

        progress_bar = new Gtk.ProgressBar ();
        progress_bar.set_name ("installer_progress");
        progress_bar.set_margin_top (8);
        box.append (progress_bar);

        checklist_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        checklist_box.set_margin_top (16);
        checklist_box.set_name ("installer_checklist");
        box.append (checklist_box);

        return box;
    }

    private Gtk.Widget build_done () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
        box.set_margin_start (48);
        box.set_margin_end (48);
        box.set_margin_top (48);
        box.set_valign (Gtk.Align.CENTER);
        box.set_vexpand (true);

        var icon = new Gtk.Label ("✓");
        icon.add_css_class ("title-1");
        icon.add_css_class ("success");
        box.append (icon);

        var title = new Gtk.Label ("Installation Complete!");
        title.add_css_class ("title-1");
        title.set_name ("installer_done_label");
        box.append (title);

        var desc = new Gtk.Label ("rawenv is ready. Get started:");
        desc.add_css_class ("dim-label");
        box.append (desc);

        var terminal = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
        terminal.add_css_class ("card");
        terminal.set_margin_top (16);
        terminal.set_margin_start (32);
        terminal.set_margin_end (32);
        string[] cmds = { "cd my-project", "rawenv init", "rawenv up" };
        foreach (var cmd in cmds) {
            var lbl = new Gtk.Label ("$ %s".printf (cmd));
            lbl.set_halign (Gtk.Align.START);
            lbl.add_css_class ("monospace");
            lbl.set_margin_start (16);
            lbl.set_margin_top (4);
            lbl.set_margin_bottom (4);
            terminal.append (lbl);
        }
        box.append (terminal);

        var continue_btn = new Gtk.Button.with_label ("Continue to Dashboard");
        continue_btn.add_css_class ("suggested-action");
        continue_btn.add_css_class ("pill");
        continue_btn.set_name ("installer_continue_button");
        continue_btn.set_halign (Gtk.Align.CENTER);
        continue_btn.set_margin_top (24);
        box.append (continue_btn);

        return box;
    }
}
