public class Rawenv.DashboardView : Adw.Bin {
    private DashboardViewModel vm;
    private MockServiceManager service_mgr;
    private Gtk.Box service_list_box;

    public DashboardView (DashboardViewModel vm) {
        this.vm = vm;
        this.service_mgr = new MockServiceManager (new MockDataRepository ());
        vm.load ();
        build_ui ();
        service_mgr.services_changed.connect (rebuild_service_list);
    }

    private void build_ui () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.set_margin_start (24);
        box.set_margin_end (24);
        box.set_margin_top (20);

        var title = new Gtk.Label ("Dashboard");
        title.add_css_class ("title-1");
        title.set_halign (Gtk.Align.START);
        title.set_name ("dashboard_title");
        box.append (title);

        box.append (build_stats_row ());
        box.append (build_service_list ());
        box.append (build_tabs ());

        this.set_child (box);
    }

    private Gtk.Widget build_stats_row () {
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        row.set_margin_top (8);
        int running = service_mgr.running_count ();
        int total = (int) service_mgr.services.length;
        row.append (make_stat_card ("CPU", "11.6%", 0.12));
        row.append (make_stat_card ("Memory", "462 MB", 0.45));
        row.append (make_stat_card ("Running", "%d / %d".printf (running, total), (double) running / (double) total));
        return row;
    }

    private Gtk.Widget make_stat_card (string label, string value, double fraction) {
        var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        card.add_css_class ("stats-card");
        card.set_hexpand (true);
        var lbl = new Gtk.Label (label);
        lbl.add_css_class ("caption");
        lbl.add_css_class ("dim-label");
        lbl.set_halign (Gtk.Align.START);
        card.append (lbl);
        var val_lbl = new Gtk.Label (value);
        val_lbl.add_css_class ("title-1");
        val_lbl.set_halign (Gtk.Align.START);
        card.append (val_lbl);
        var bar = new Gtk.ProgressBar ();
        bar.set_fraction (fraction);
        bar.set_margin_top (4);
        card.append (bar);
        return card;
    }

    private Gtk.Widget build_service_list () {
        service_list_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        service_list_box.add_css_class ("boxed-list");
        service_list_box.set_margin_top (12);
        service_list_box.set_name ("services_list");
        populate_service_list ();
        return service_list_box;
    }

    private void rebuild_service_list () {
        var child = service_list_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            service_list_box.remove (child);
            child = next;
        }
        populate_service_list ();
    }

    private void populate_service_list () {
        for (uint i = 0; i < service_mgr.services.length; i++) {
            var s = service_mgr.services[i];
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            row.set_margin_start (12);
            row.set_margin_end (12);
            row.set_margin_top (8);
            row.set_margin_bottom (8);

            var dot = new Gtk.Label ("●");
            dot.add_css_class (s.status == "running" ? "status-dot-running" : "status-dot-stopped");
            row.append (dot);

            var name_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            name_box.set_hexpand (true);
            var name_lbl = new Gtk.Label ("%s %s".printf (s.icon, s.name));
            name_lbl.set_halign (Gtk.Align.START);
            var detail_lbl = new Gtk.Label (":%d · v%s".printf (s.port, s.version));
            detail_lbl.add_css_class ("dim-label");
            detail_lbl.add_css_class ("monospace");
            detail_lbl.set_halign (Gtk.Align.START);
            name_box.append (name_lbl);
            name_box.append (detail_lbl);
            row.append (name_box);

            if (s.status == "running") {
                var metrics = new Gtk.Label ("%s · %s · %s".printf (s.cpu, s.mem, s.uptime));
                metrics.add_css_class ("dim-label");
                metrics.add_css_class ("monospace");
                row.append (metrics);
            }

            var btn = new Gtk.Button.with_label (s.status == "running" ? "Stop" : "Start");
            btn.add_css_class (s.status == "running" ? "destructive-action" : "suggested-action");
            string svc_name = s.name;
            btn.clicked.connect (() => {
                if (service_mgr.services[i].status == "running") {
                    service_mgr.stop_service (svc_name);
                } else {
                    service_mgr.start_service (svc_name);
                }
            });
            row.append (btn);
            service_list_box.append (row);
        }
    }

    private Gtk.Widget build_tabs () {
        var notebook = new Gtk.Notebook ();
        notebook.set_name ("dashboard_tabs");
        notebook.set_margin_top (12);
        notebook.set_vexpand (true);

        notebook.append_page (build_logs_tab (), new Gtk.Label ("Logs"));
        notebook.append_page (build_config_tab (), new Gtk.Label ("Config"));
        notebook.append_page (build_connection_tab (), new Gtk.Label ("Connection"));
        notebook.append_page (build_cell_tab (), new Gtk.Label ("Cell"));
        notebook.append_page (build_backups_tab (), new Gtk.Label ("Backups"));

        return notebook;
    }

    private Gtk.Widget build_logs_tab () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
        box.set_margin_start (8);
        box.set_margin_top (8);
        for (uint i = 0; i < vm.logs.length; i++) {
            var l = vm.logs[i];
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var time_lbl = new Gtk.Label (l.time);
            time_lbl.add_css_class ("dim-label");
            time_lbl.add_css_class ("monospace");
            var msg_lbl = new Gtk.Label (l.msg);
            msg_lbl.add_css_class ("monospace");
            msg_lbl.set_halign (Gtk.Align.START);
            msg_lbl.set_hexpand (true);
            msg_lbl.set_wrap (true);
            if (l.level == "warn") msg_lbl.add_css_class ("warning-text");
            if (l.level == "error") msg_lbl.add_css_class ("error-text");
            row.append (time_lbl);
            row.append (msg_lbl);
            box.append (row);
        }
        var scroll = new Gtk.ScrolledWindow ();
        scroll.set_child (box);
        scroll.set_vexpand (true);
        return scroll;
    }

    private Gtk.Widget build_config_tab () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        box.set_margin_start (12);
        box.set_margin_top (12);
        var lbl = new Gtk.Label ("# rawenv.toml\nname = \"utilio\"\nversion = \"1\"\n\n[services.node]\nversion = \"22\"\n\n[services.postgres]\nversion = \"16\"\n\n[services.redis]\nversion = \"7\"");
        lbl.add_css_class ("monospace");
        lbl.set_halign (Gtk.Align.START);
        box.append (lbl);
        return box;
    }

    private Gtk.Widget build_connection_tab () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        box.set_margin_start (12);
        box.set_margin_top (12);
        var lbl = new Gtk.Label ("DATABASE_URL → localhost:5432\nREDIS_URL → localhost:6379\nMEILISEARCH_URL → localhost:7700");
        lbl.add_css_class ("monospace");
        lbl.set_halign (Gtk.Align.START);
        box.append (lbl);
        return box;
    }

    private Gtk.Widget build_cell_tab () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        box.set_margin_start (12);
        box.set_margin_top (12);
        var lbl = new Gtk.Label ("Isolation: Namespaces + Landlock\nMemory Limit: 256MB\nCPU Limit: 1 core\nNetwork: Isolated");
        lbl.add_css_class ("monospace");
        lbl.set_halign (Gtk.Align.START);
        box.append (lbl);
        return box;
    }

    private Gtk.Widget build_backups_tab () {
        var status = new Adw.StatusPage ();
        status.set_title ("No Backups");
        status.set_description ("Use `rawenv backup create` to snapshot service data.");
        status.set_icon_name ("drive-harddisk-symbolic");
        return status;
    }
}
