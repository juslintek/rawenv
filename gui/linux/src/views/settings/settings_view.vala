public class Rawenv.SettingsView : Adw.Bin {
    private SettingsViewModel vm;

    public SettingsView (SettingsViewModel vm) {
        this.vm = vm;
        vm.load ();
        build_ui ();
    }

    private void build_ui () {
        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
        paned.set_name ("settings_paned");

        var sidebar = new Gtk.ListBox ();
        sidebar.set_name ("settings_sidebar");
        sidebar.add_css_class ("navigation-sidebar");
        string[] pages = { "General", "Services", "Runtimes", "Network", "Cells", "Deploy", "AI", "Theme", "About" };
        foreach (var p in pages) {
            var row = new Gtk.Label (p);
            row.set_halign (Gtk.Align.START);
            row.set_margin_start (12);
            row.set_margin_end (12);
            row.set_margin_top (8);
            row.set_margin_bottom (8);
            sidebar.append (row);
        }
        sidebar.set_size_request (160, -1);
        paned.set_start_child (sidebar);

        var stack = new Gtk.Stack ();
        stack.set_name ("settings_stack");
        stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
        stack.add_named (build_general_page (), "general");
        stack.add_named (build_services_page (), "services");
        stack.add_named (build_runtimes_page (), "runtimes");
        stack.add_named (build_network_page (), "network");
        stack.add_named (build_cells_page (), "cells");
        stack.add_named (build_deploy_page (), "deploy");
        stack.add_named (build_ai_page (), "ai");
        stack.add_named (build_theme_page (), "theme");
        stack.add_named (build_about_page (), "about");

        sidebar.row_selected.connect ((row) => {
            if (row != null) {
                var idx = row.get_index ();
                string[] names = { "general", "services", "runtimes", "network", "cells", "deploy", "ai", "theme", "about" };
                if (idx >= 0 && idx < names.length) {
                    stack.set_visible_child_name (names[idx]);
                }
            }
        });

        paned.set_end_child (stack);
        this.set_child (paned);
    }

    private Gtk.Widget build_general_page () {
        var group = new Adw.PreferencesGroup ();
        group.set_title ("General");
        group.set_name ("settings_general");
        var store_row = new Adw.ActionRow ();
        store_row.set_title ("Store Location");
        store_row.set_subtitle (vm.settings.store_location);
        group.add (store_row);
        var auto_start = new Adw.SwitchRow ();
        auto_start.set_title ("Auto-start Services");
        auto_start.set_active (vm.settings.auto_start_services);
        auto_start.set_name ("auto_start_switch");
        group.add (auto_start);
        var auto_detect = new Adw.SwitchRow ();
        auto_detect.set_title ("Auto-detect Projects");
        auto_detect.set_active (vm.settings.auto_detect_projects);
        group.add (auto_detect);
        var launch = new Adw.SwitchRow ();
        launch.set_title ("Launch at Login");
        launch.set_active (vm.settings.launch_at_login);
        group.add (launch);
        var watcher = new Adw.SwitchRow ();
        watcher.set_title ("File Watcher");
        watcher.set_active (vm.settings.file_watcher);
        group.add (watcher);
        var page = new Adw.PreferencesPage ();
        page.add (group);
        return page;
    }

    private Gtk.Widget build_services_page () {
        var group = new Adw.PreferencesGroup ();
        group.set_title ("Services");
        group.set_name ("settings_services");
        group.set_description ("Manage configured services and their lifecycle.");
        string[,] services = {
            {"PostgreSQL", "16", ":5432"},
            {"Redis", "7", ":6379"},
            {"Meilisearch", "1.6", ":7700"},
            {"Node.js", "22", "runtime"},
            {"Caddy", "2.7", ":443"}
        };
        for (int i = 0; i < 5; i++) {
            var row = new Adw.ActionRow ();
            row.set_title (services[i, 0]);
            row.set_subtitle ("v%s — %s".printf (services[i, 1], services[i, 2]));
            group.add (row);
        }
        var page = new Adw.PreferencesPage ();
        page.add (group);
        return page;
    }

    private Gtk.Widget build_runtimes_page () {
        var group = new Adw.PreferencesGroup ();
        group.set_title ("Runtimes");
        group.set_name ("settings_runtimes");
        group.set_description ("Installed runtime versions and store paths.");
        string[,] runtimes = {
            {"Node.js", "22.15.0", "~/.rawenv/store/node-22/"},
            {"PostgreSQL", "16.4", "~/.rawenv/store/postgres-16/"},
            {"Redis", "7.4.1", "~/.rawenv/store/redis-7/"}
        };
        for (int i = 0; i < 3; i++) {
            var row = new Adw.ActionRow ();
            row.set_title ("%s %s".printf (runtimes[i, 0], runtimes[i, 1]));
            row.set_subtitle (runtimes[i, 2]);
            group.add (row);
        }
        var page = new Adw.PreferencesPage ();
        page.add (group);
        return page;
    }

    private Gtk.Widget build_network_page () {
        var group = new Adw.PreferencesGroup ();
        group.set_title ("Network");
        group.set_name ("settings_network");
        var domain_row = new Adw.EntryRow ();
        domain_row.set_title ("Local Domain");
        domain_row.set_text (vm.settings.local_domain);
        group.add (domain_row);
        var tls = new Adw.SwitchRow ();
        tls.set_title ("Auto TLS");
        tls.set_active (vm.settings.auto_tls);
        group.add (tls);
        var port_row = new Adw.ActionRow ();
        port_row.set_title ("Proxy Port");
        port_row.set_subtitle ("%d".printf (vm.settings.proxy_port));
        group.add (port_row);
        var tunnel_row = new Adw.ActionRow ();
        tunnel_row.set_title ("Tunnel Provider");
        tunnel_row.set_subtitle (vm.settings.tunnel_provider);
        group.add (tunnel_row);
        var page = new Adw.PreferencesPage ();
        page.add (group);
        return page;
    }

    private Gtk.Widget build_cells_page () {
        var group = new Adw.PreferencesGroup ();
        group.set_title ("Cells (Isolation)");
        group.set_name ("settings_cells");
        var enabled = new Adw.SwitchRow ();
        enabled.set_title ("Enable by Default");
        enabled.set_active (vm.settings.cells_enabled);
        group.add (enabled);
        var mem_row = new Adw.ActionRow ();
        mem_row.set_title ("Default Memory Limit");
        mem_row.set_subtitle (vm.settings.default_memory_limit);
        group.add (mem_row);
        var backends_row = new Adw.ActionRow ();
        backends_row.set_title ("Available Backends");
        backends_row.set_subtitle ("cgroups v2, namespaces, Landlock");
        group.add (backends_row);
        var page = new Adw.PreferencesPage ();
        page.add (group);
        return page;
    }

    private Gtk.Widget build_deploy_page () {
        var group = new Adw.PreferencesGroup ();
        group.set_title ("Deploy");
        group.set_name ("settings_deploy");
        var provider_row = new Adw.ComboRow ();
        provider_row.set_title ("Provider");
        provider_row.set_model (new Gtk.StringList ({ "Hetzner", "DigitalOcean", "AWS", "GCP", "Azure" }));
        group.add (provider_row);
        var region_row = new Adw.ActionRow ();
        region_row.set_title ("Default Region");
        region_row.set_subtitle ("eu-central-1");
        group.add (region_row);
        var page = new Adw.PreferencesPage ();
        page.add (group);
        return page;
    }

    private Gtk.Widget build_ai_page () {
        var page = new Adw.PreferencesPage ();

        // Provider group
        var provider_group = new Adw.PreferencesGroup ();
        provider_group.set_title ("AI Provider");
        provider_group.set_name ("settings_ai");

        var provider_row = new Adw.ComboRow ();
        provider_row.set_title ("Provider");
        provider_row.set_name ("ai_provider_select");
        provider_row.set_model (new Gtk.StringList (vm.ai_providers));
        provider_group.add (provider_row);

        var endpoint_row = new Adw.EntryRow ();
        endpoint_row.set_title ("Custom Endpoint (BYOM)");
        endpoint_row.set_text (vm.settings.ai_custom_endpoint);
        endpoint_row.set_name ("ai_custom_endpoint");
        provider_group.add (endpoint_row);

        var key_row = new Adw.PasswordEntryRow ();
        key_row.set_title ("API Key");
        key_row.set_name ("ai_api_key");
        provider_group.add (key_row);

        var model_row = new Adw.EntryRow ();
        model_row.set_title ("Model Name");
        model_row.set_text ("llama-3.3-70b");
        model_row.set_name ("ai_model_name");
        provider_group.add (model_row);

        page.add (provider_group);

        // Autonomy group
        var autonomy_group = new Adw.PreferencesGroup ();
        autonomy_group.set_title ("Autonomy");
        autonomy_group.set_name ("ai_autonomy_group");

        var autonomy_row = new Adw.ComboRow ();
        autonomy_row.set_title ("Default Autonomy Level");
        autonomy_row.set_name ("ai_autonomy_level");
        autonomy_row.set_model (new Gtk.StringList (vm.autonomy_levels));
        autonomy_group.add (autonomy_row);

        var proactive = new Adw.SwitchRow ();
        proactive.set_title ("Proactive Suggestions");
        proactive.set_active (vm.settings.proactive_suggestions);
        proactive.set_name ("ai_proactive_suggestions");
        autonomy_group.add (proactive);

        var auto_apply = new Adw.SwitchRow ();
        auto_apply.set_title ("Auto-apply Safe Fixes");
        auto_apply.set_active (vm.settings.auto_apply_safe);
        auto_apply.set_name ("ai_auto_apply_safe");
        autonomy_group.add (auto_apply);

        page.add (autonomy_group);

        // Per-action autonomy group
        var per_action_group = new Adw.PreferencesGroup ();
        per_action_group.set_title ("Per-Action Autonomy");
        per_action_group.set_name ("ai_per_action_autonomy");

        string[] actions = { "Optimize Config", "Restart Service", "Deploy", "Delete Data", "Install Runtime" };
        foreach (var action in actions) {
            var action_row = new Adw.ComboRow ();
            action_row.set_title (action);
            action_row.set_name ("autonomy_%s".printf (action.down ().replace (" ", "_")));
            action_row.set_model (new Gtk.StringList (vm.autonomy_levels));
            per_action_group.add (action_row);
        }

        page.add (per_action_group);
        return page;
    }

    private Gtk.Widget build_theme_page () {
        var group = new Adw.PreferencesGroup ();
        group.set_title ("Theme");
        group.set_name ("settings_theme");
        var mode_row = new Adw.ComboRow ();
        mode_row.set_title ("Mode");
        mode_row.set_model (new Gtk.StringList ({ "dark", "light", "system" }));
        group.add (mode_row);
        var accent_row = new Adw.ActionRow ();
        accent_row.set_title ("Accent Color");
        accent_row.set_subtitle (vm.settings.accent_color);
        group.add (accent_row);
        var font_row = new Adw.ActionRow ();
        font_row.set_title ("Font Size");
        font_row.set_subtitle ("%d px".printf (vm.settings.font_size));
        group.add (font_row);
        var page = new Adw.PreferencesPage ();
        page.add (group);
        return page;
    }

    private Gtk.Widget build_about_page () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.set_margin_start (24);
        box.set_margin_top (24);
        box.set_name ("settings_about");
        box.set_valign (Gtk.Align.CENTER);
        box.set_vexpand (true);

        var logo = new Gtk.Label ("⚡");
        logo.add_css_class ("title-1");
        box.append (logo);
        var title = new Gtk.Label ("rawenv");
        title.add_css_class ("title-1");
        box.append (title);
        var ver = new Gtk.Label ("Version 0.1.0");
        ver.add_css_class ("dim-label");
        box.append (ver);
        var desc = new Gtk.Label ("Native dev environments. Zero dependencies. One binary.");
        desc.set_wrap (true);
        desc.add_css_class ("dim-label");
        box.append (desc);
        var links = new Gtk.Label ("GitHub · Documentation · License: MIT");
        links.add_css_class ("dim-label");
        links.set_margin_top (16);
        box.append (links);
        return box;
    }
}
