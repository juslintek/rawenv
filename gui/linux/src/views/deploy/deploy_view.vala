public class Rawenv.DeployView : Adw.Bin {
    private DeployViewModel vm;
    private MockDeployEngine engine;
    private Gtk.Box log_box;
    private Gtk.ProgressBar deploy_progress;
    private Gtk.Button deploy_btn;
    private Gtk.Button fix_btn;

    public DeployView (DeployViewModel vm) {
        this.vm = vm;
        this.engine = new MockDeployEngine ();
        vm.load ();
        build_ui ();
        engine.updated.connect (refresh_log);
    }

    private void build_ui () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        box.set_margin_start (16);
        box.set_margin_end (16);
        box.set_margin_top (16);

        var title = new Gtk.Label ("Deploy");
        title.add_css_class ("title-1");
        title.set_halign (Gtk.Align.START);
        box.append (title);

        var notebook = new Gtk.Notebook ();
        notebook.set_name ("deploy_tabs");

        // Terraform tab
        var tf_view = new Gtk.TextView ();
        tf_view.get_buffer ().set_text (vm.terraform, -1);
        tf_view.set_editable (false);
        tf_view.add_css_class ("monospace");
        tf_view.set_name ("deploy_terraform");
        var tf_scroll = new Gtk.ScrolledWindow ();
        tf_scroll.set_child (tf_view);
        tf_scroll.set_vexpand (true);
        notebook.append_page (tf_scroll, new Gtk.Label ("Terraform"));

        // Ansible tab
        var ans_view = new Gtk.TextView ();
        ans_view.get_buffer ().set_text (vm.ansible, -1);
        ans_view.set_editable (false);
        ans_view.add_css_class ("monospace");
        ans_view.set_name ("deploy_ansible");
        var ans_scroll = new Gtk.ScrolledWindow ();
        ans_scroll.set_child (ans_view);
        notebook.append_page (ans_scroll, new Gtk.Label ("Ansible"));

        // Containerfile tab
        var cf_view = new Gtk.TextView ();
        cf_view.get_buffer ().set_text (vm.containerfile, -1);
        cf_view.set_editable (false);
        cf_view.add_css_class ("monospace");
        cf_view.set_name ("deploy_containerfile");
        var cf_scroll = new Gtk.ScrolledWindow ();
        cf_scroll.set_child (cf_view);
        notebook.append_page (cf_scroll, new Gtk.Label ("Containerfile"));

        // Deploy Log tab
        var log_page = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        log_page.set_margin_start (12);
        log_page.set_margin_end (12);
        log_page.set_margin_top (12);

        deploy_progress = new Gtk.ProgressBar ();
        deploy_progress.set_name ("deploy_progress");
        log_page.append (deploy_progress);

        log_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
        log_box.add_css_class ("deploy-log");
        log_box.set_name ("deploy_log_output");
        var log_scroll = new Gtk.ScrolledWindow ();
        log_scroll.set_child (log_box);
        log_scroll.set_vexpand (true);
        log_page.append (log_scroll);

        var btn_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        btn_row.set_margin_top (8);
        btn_row.set_margin_bottom (8);

        deploy_btn = new Gtk.Button.with_label ("Deploy (Dry Run)");
        deploy_btn.set_name ("deploy_apply_button");
        deploy_btn.add_css_class ("suggested-action");
        deploy_btn.clicked.connect (() => engine.start_deploy ());
        btn_row.append (deploy_btn);

        fix_btn = new Gtk.Button.with_label ("🤖 AI Fix");
        fix_btn.set_name ("deploy_ai_fix_button");
        fix_btn.add_css_class ("suggested-action");
        fix_btn.set_sensitive (false);
        fix_btn.clicked.connect (() => engine.apply_ai_fix ());
        btn_row.append (fix_btn);

        log_page.append (btn_row);
        notebook.append_page (log_page, new Gtk.Label ("Deploy Log"));

        box.append (notebook);
        this.set_child (box);
    }

    private void refresh_log () {
        deploy_progress.set_fraction (engine.progress);
        deploy_btn.set_sensitive (!engine.is_running);
        fix_btn.set_sensitive (engine.has_error);

        var child = log_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            log_box.remove (child);
            child = next;
        }
        for (uint i = 0; i < engine.logs.length; i++) {
            var entry = engine.logs[i];
            var lbl = new Gtk.Label (entry.text);
            lbl.set_halign (Gtk.Align.START);
            lbl.set_wrap (true);
            lbl.add_css_class ("monospace");
            if (entry.is_error) lbl.add_css_class ("deploy-log-error");
            log_box.append (lbl);
        }
    }
}
