public class Rawenv.MainWindow : Adw.ApplicationWindow {
    private DataRepository repo;
    private AiProvider ai_provider;
    private Gtk.Stack content_stack;
    private string[] nav_items = { "Dashboard", "AI Chat", "Connections", "Deploy", "Tunnel", "Projects", "Settings", "Installer", "Uninstall" };

    public MainWindow (Adw.Application app) {
        Object (application: app);
        this.set_title ("Rawenv");
        this.set_default_size (1024, 768);
        this.set_name ("Rawenv");

        repo = new MockDataRepository ();
        ai_provider = new MockAiProvider ();
        build_ui ();
    }

    private void build_ui () {
        var split = new Adw.NavigationSplitView ();

        // Sidebar
        var sidebar_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        sidebar_box.add_css_class ("sidebar-panel");
        sidebar_box.set_vexpand (true);
        var sidebar_list = new Gtk.ListBox ();
        sidebar_list.set_name ("navigation_sidebar");
        sidebar_list.add_css_class ("navigation-sidebar");

        foreach (var item in this.nav_items) {
            var row = new Gtk.Label (item);
            row.set_halign (Gtk.Align.START);
            row.set_margin_start (12);
            row.set_margin_end (12);
            row.set_margin_top (10);
            row.set_margin_bottom (10);
            sidebar_list.append (row);
        }
        sidebar_box.append (sidebar_list);

        var sidebar_page = new Adw.NavigationPage (sidebar_box, "Rawenv");
        split.set_sidebar (sidebar_page);

        // Content
        content_stack = new Gtk.Stack ();
        content_stack.set_name ("content_stack");
        content_stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);

        content_stack.add_named (new DashboardView (new DashboardViewModel (repo)), "Dashboard");
        content_stack.add_named (new AiChatView (new AiChatViewModel (repo, ai_provider)), "AI Chat");
        content_stack.add_named (new ConnectionsView (new ConnectionsViewModel (repo)), "Connections");
        content_stack.add_named (new DeployView (new DeployViewModel (repo)), "Deploy");
        content_stack.add_named (new TunnelView (), "Tunnel");
        content_stack.add_named (new ProjectsView (new ProjectsViewModel (repo)), "Projects");
        content_stack.add_named (new SettingsView (new SettingsViewModel (repo)), "Settings");
        content_stack.add_named (new InstallerView (new InstallerViewModel ()), "Installer");
        content_stack.add_named (new UninstallView (), "Uninstall");

        sidebar_list.row_selected.connect ((row) => {
            if (row != null) {
                var idx = row.get_index ();
                if (idx >= 0 && idx < this.nav_items.length) {
                    content_stack.set_visible_child_name (this.nav_items[idx]);
                }
            }
        });

        var content_page = new Adw.NavigationPage (content_stack, "Content");
        split.set_content (content_page);

        this.set_content (split);
    }
}
