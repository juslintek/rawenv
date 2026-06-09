public class Rawenv.MockDataRepository : Object, DataRepository {
    private Json.Node root;

    public MockDataRepository () {
        try {
            var parser = new Json.Parser ();
            string[] paths = {
                "../shared/mock-data.json",
                "../../shared/mock-data.json",
                "../../../shared/mock-data.json",
                "shared/mock-data.json"
            };
            bool loaded = false;
            foreach (var p in paths) {
                if (FileUtils.test (p, FileTest.EXISTS)) {
                    parser.load_from_file (p);
                    loaded = true;
                    break;
                }
            }
            if (!loaded) {
                parser.load_from_data ("{\"services\":[],\"logs\":[],\"aiMessages\":[],\"connections\":[],\"projects\":[],\"settings\":{},\"deploy\":{}}");
            }
            root = parser.get_root ();
        } catch (Error e) {
            warning ("Failed to load mock data: %s", e.message);
            try {
                var parser = new Json.Parser ();
                parser.load_from_data ("{}");
                root = parser.get_root ();
            } catch (Error e2) {}
        }
    }

    public GenericArray<Service> get_services () {
        var arr = new GenericArray<Service> ();
        var jarr = root.get_object ().get_array_member ("services");
        for (uint i = 0; i < jarr.get_length (); i++) {
            var obj = jarr.get_object_element (i);
            var s = new Service ();
            s.name = obj.get_string_member ("name");
            s.port = (int) obj.get_int_member ("port");
            s.version = obj.get_string_member ("version");
            s.pid = obj.has_member ("pid") && obj.get_member ("pid").get_node_type () != Json.NodeType.NULL ? (int) obj.get_int_member ("pid") : 0;
            s.cpu = obj.has_member ("cpu") && obj.get_member ("cpu").get_node_type () != Json.NodeType.NULL ? obj.get_string_member ("cpu") : "";
            s.mem = obj.has_member ("mem") && obj.get_member ("mem").get_node_type () != Json.NodeType.NULL ? obj.get_string_member ("mem") : "";
            s.uptime = obj.has_member ("uptime") && obj.get_member ("uptime").get_node_type () != Json.NodeType.NULL ? obj.get_string_member ("uptime") : "";
            s.status = obj.get_string_member ("status");
            s.icon = obj.get_string_member ("icon");
            arr.add (s);
        }
        return arr;
    }

    public GenericArray<LogEntry> get_logs () {
        var arr = new GenericArray<LogEntry> ();
        var jarr = root.get_object ().get_array_member ("logs");
        for (uint i = 0; i < jarr.get_length (); i++) {
            var obj = jarr.get_object_element (i);
            var l = new LogEntry ();
            l.time = obj.get_string_member ("time");
            l.msg = obj.get_string_member ("msg");
            l.level = obj.get_string_member ("level");
            arr.add (l);
        }
        return arr;
    }

    public GenericArray<AiMessage> get_ai_messages () {
        var arr = new GenericArray<AiMessage> ();
        var jarr = root.get_object ().get_array_member ("aiMessages");
        for (uint i = 0; i < jarr.get_length (); i++) {
            var obj = jarr.get_object_element (i);
            var m = new AiMessage ();
            m.role = obj.get_string_member ("role");
            m.text = obj.get_string_member ("text");
            arr.add (m);
        }
        return arr;
    }

    public GenericArray<Connection> get_connections () {
        var arr = new GenericArray<Connection> ();
        var jarr = root.get_object ().get_array_member ("connections");
        for (uint i = 0; i < jarr.get_length (); i++) {
            var obj = jarr.get_object_element (i);
            var c = new Connection ();
            c.env_var = obj.get_string_member ("envVar");
            c.original = obj.get_string_member ("original");
            c.local = obj.has_member ("local") ? obj.get_string_member ("local") : "";
            c.mode = obj.get_string_member ("mode");
            c.badge = obj.get_string_member ("badge");
            c.proxy = obj.has_member ("proxy") ? obj.get_string_member ("proxy") : "";
            c.alternative = obj.has_member ("alternative") ? obj.get_string_member ("alternative") : "";
            arr.add (c);
        }
        return arr;
    }

    public GenericArray<Project> get_projects () {
        var arr = new GenericArray<Project> ();
        var jarr = root.get_object ().get_array_member ("projects");
        for (uint i = 0; i < jarr.get_length (); i++) {
            var obj = jarr.get_object_element (i);
            var p = new Project ();
            p.name = obj.get_string_member ("name");
            p.path = obj.get_string_member ("path");
            p.deps = obj.get_string_member ("deps");
            var stack_arr = obj.get_array_member ("stack");
            string[] stack = {};
            for (uint j = 0; j < stack_arr.get_length (); j++) {
                stack += stack_arr.get_string_element (j);
            }
            p.stack = stack;
            arr.add (p);
        }
        return arr;
    }

    public Settings get_settings () {
        var s = new Settings ();
        var obj = root.get_object ().get_object_member ("settings");
        var gen = obj.get_object_member ("general");
        s.store_location = gen.get_string_member ("storeLocation");
        s.auto_start_services = gen.get_boolean_member ("autoStartServices");
        s.auto_detect_projects = gen.get_boolean_member ("autoDetectProjects");
        s.launch_at_login = gen.get_boolean_member ("launchAtLogin");
        s.file_watcher = gen.get_boolean_member ("fileWatcher");
        var net = obj.get_object_member ("network");
        s.local_domain = net.get_string_member ("localDomain");
        s.auto_tls = net.get_boolean_member ("autoTls");
        s.proxy_port = (int) net.get_int_member ("proxyPort");
        s.tunnel_provider = net.get_string_member ("tunnelProvider");
        var cells = obj.get_object_member ("cells");
        s.cells_enabled = cells.get_boolean_member ("enableByDefault");
        s.default_memory_limit = cells.get_string_member ("defaultMemoryLimit");
        var deploy = obj.get_object_member ("deploy");
        s.deploy_provider = deploy.get_string_member ("provider");
        var ai = obj.get_object_member ("ai");
        s.ai_provider = ai.get_string_member ("provider");
        s.ai_api_key = ai.get_string_member ("apiKey");
        s.proactive_suggestions = ai.get_boolean_member ("proactiveSuggestions");
        s.auto_apply_safe = ai.get_boolean_member ("autoApplySafeFixes");
        s.default_autonomy = ai.get_string_member ("defaultAutonomy");
        var theme = obj.get_object_member ("theme");
        s.theme_mode = theme.get_string_member ("mode");
        s.accent_color = theme.get_string_member ("accentColor");
        s.font_size = (int) theme.get_int_member ("fontSize");
        return s;
    }

    public string get_deploy_terraform () {
        return root.get_object ().get_object_member ("deploy").get_string_member ("terraform");
    }

    public string get_deploy_ansible () {
        return root.get_object ().get_object_member ("deploy").get_string_member ("ansible");
    }

    public string get_deploy_containerfile () {
        return root.get_object ().get_object_member ("deploy").get_string_member ("containerfile");
    }
}
