public class Rawenv.ProjectsView : Adw.Bin {
    private ProjectsViewModel vm;
    private MockScannerEngine scanner;
    private Gtk.Stack main_stack;
    private Gtk.Box discovery_list;
    private Gtk.Label total_label;
    private Gtk.ListBox projects_list;

    public ProjectsView (ProjectsViewModel vm) {
        this.vm = vm;
        this.scanner = new MockScannerEngine ();
        vm.load ();
        build_ui ();
        scanner.scan_updated.connect (() => {
            total_label.set_text ("%d projects found".printf (scanner.total_projects));
            rebuild_discovery_list ();
        });
    }

    private void rebuild_discovery_list () {
        var child = discovery_list.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            discovery_list.remove (child);
            child = next;
        }
        for (uint i = 0; i < scanner.paths.length; i++) {
            var sp = scanner.paths[i];
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            row.set_margin_start (12);
            row.set_margin_end (12);
            row.set_margin_top (6);
            row.set_margin_bottom (6);

            string icon = sp.status == "done" ? "✓" : (sp.status == "scanning" ? "⟳" : "○");
            var status_lbl = new Gtk.Label (icon);
            status_lbl.add_css_class (sp.status == "done" ? "success" : "dim-label");
            var path_lbl = new Gtk.Label (sp.path);
            path_lbl.set_hexpand (true);
            path_lbl.set_halign (Gtk.Align.START);
            path_lbl.add_css_class ("monospace");
            var count_lbl = new Gtk.Label (sp.status == "done" ? "%d projects".printf (sp.project_count) : "—");
            count_lbl.add_css_class ("dim-label");

            if (sp.cached) {
                var cached_badge = new Gtk.Label ("cached");
                cached_badge.add_css_class ("dim-label");
                cached_badge.add_css_class ("caption");
                row.append (status_lbl);
                row.append (path_lbl);
                row.append (cached_badge);
                row.append (count_lbl);
            } else {
                row.append (status_lbl);
                row.append (path_lbl);
                row.append (count_lbl);
            }
            discovery_list.append (row);
        }
    }

    private void build_ui () {
        main_stack = new Gtk.Stack ();
        main_stack.set_name ("projects_stack");
        main_stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
        main_stack.add_named (build_discovery (), "discovery");
        main_stack.add_named (build_project_list (), "list");
        main_stack.add_named (build_project_setup (), "setup");
        main_stack.set_visible_child_name ("list");
        this.set_child (main_stack);
    }

    private Gtk.Widget build_discovery () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.set_margin_start (24);
        box.set_margin_end (24);
        box.set_margin_top (24);

        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        var title = new Gtk.Label ("Discover Projects");
        title.add_css_class ("title-2");
        title.set_hexpand (true);
        title.set_halign (Gtk.Align.START);
        var scan_btn = new Gtk.Button.with_label ("Scan");
        scan_btn.add_css_class ("suggested-action");
        scan_btn.set_name ("scan_button");
        scan_btn.clicked.connect (() => scanner.start_scan ());
        header.append (title);
        header.append (scan_btn);
        box.append (header);

        total_label = new Gtk.Label ("%d projects found".printf (scanner.total_projects));
        total_label.add_css_class ("dim-label");
        total_label.set_halign (Gtk.Align.START);
        box.append (total_label);

        discovery_list = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        discovery_list.add_css_class ("card");
        discovery_list.set_name ("discovery_paths");
        box.append (discovery_list);
        rebuild_discovery_list ();

        var done_btn = new Gtk.Button.with_label ("View Projects");
        done_btn.set_margin_top (12);
        done_btn.set_halign (Gtk.Align.END);
        done_btn.clicked.connect (() => main_stack.set_visible_child_name ("list"));
        box.append (done_btn);

        return box;
    }

    private Gtk.Widget build_project_list () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        box.set_margin_start (24);
        box.set_margin_end (24);
        box.set_margin_top (24);

        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        var title = new Gtk.Label ("Projects");
        title.add_css_class ("title-2");
        title.set_hexpand (true);
        title.set_halign (Gtk.Align.START);
        var discover_btn = new Gtk.Button.with_label ("Discover");
        discover_btn.set_name ("discover_projects_button");
        discover_btn.clicked.connect (() => main_stack.set_visible_child_name ("discovery"));
        header.append (title);
        header.append (discover_btn);
        box.append (header);

        var search = new Gtk.SearchEntry ();
        search.set_placeholder_text ("Filter projects…");
        search.set_name ("projects_search");
        search.search_changed.connect (() => {
            vm.search_query = search.get_text ();
            rebuild_project_list ();
        });
        box.append (search);

        projects_list = new Gtk.ListBox ();
        projects_list.set_name ("projects_list");
        projects_list.add_css_class ("boxed-list");
        projects_list.row_selected.connect ((row) => {
            if (row != null) main_stack.set_visible_child_name ("setup");
        });
        rebuild_project_list ();

        var scroll = new Gtk.ScrolledWindow ();
        scroll.set_child (projects_list);
        scroll.set_vexpand (true);
        box.append (scroll);

        return box;
    }

    private void rebuild_project_list () {
        var child = projects_list.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            projects_list.remove (child);
            child = next;
        }
        var filtered = vm.filtered_projects ();
        for (uint i = 0; i < filtered.length; i++) {
            var p = filtered[i];
            var row = new Adw.ActionRow ();
            row.set_title (p.name);
            row.set_subtitle (p.path);
            row.set_name ("project_%s".printf (p.name));
            var tags_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            foreach (var tag in p.stack) {
                var badge = new Gtk.Label (tag);
                badge.add_css_class ("caption");
                badge.add_css_class ("card");
                badge.set_margin_start (2);
                badge.set_margin_end (2);
                tags_box.append (badge);
            }
            row.add_suffix (tags_box);
            projects_list.append (row);
        }
    }

    private Gtk.Widget build_project_setup () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.set_margin_start (24);
        box.set_margin_end (24);
        box.set_margin_top (24);

        var back_btn = new Gtk.Button.with_label ("← Back to Projects");
        back_btn.set_halign (Gtk.Align.START);
        back_btn.clicked.connect (() => main_stack.set_visible_child_name ("list"));
        box.append (back_btn);

        var title = new Gtk.Label ("Project Setup");
        title.add_css_class ("title-2");
        title.set_halign (Gtk.Align.START);
        box.append (title);

        box.append (make_section_card ("Runtimes", {
            "Node.js 22.15 — active",
            "PostgreSQL 18.2 — active",
            "Redis 7.4 — active"
        }));
        box.append (make_section_card ("Services", {
            "PostgreSQL :5432 — running",
            "Redis :6379 — running",
            "Meilisearch :7700 — running"
        }));
        box.append (make_section_card ("Connections", {
            "DATABASE_URL → localhost:5432",
            "REDIS_URL → localhost:6379",
            "MEILISEARCH_URL → localhost:7700"
        }));

        return box;
    }

    private Gtk.Widget make_section_card (string heading, string[] items) {
        var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
        card.add_css_class ("card");
        card.set_margin_top (8);
        var h = new Gtk.Label (heading);
        h.add_css_class ("heading");
        h.set_halign (Gtk.Align.START);
        h.set_margin_start (12);
        h.set_margin_top (8);
        card.append (h);
        foreach (var item in items) {
            var lbl = new Gtk.Label (item);
            lbl.set_halign (Gtk.Align.START);
            lbl.set_margin_start (12);
            lbl.set_margin_top (4);
            lbl.set_margin_bottom (4);
            lbl.add_css_class ("monospace");
            card.append (lbl);
        }
        return card;
    }
}
