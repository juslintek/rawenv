public class Rawenv.DeployLogEntry : Object {
    public string text { get; set; default = ""; }
    public bool is_error { get; set; default = false; }
}

public class Rawenv.MockDeployEngine : Object {
    public GenericArray<DeployLogEntry> logs { get; owned set; }
    public double progress { get; set; default = 0.0; }
    public bool is_running { get; set; default = false; }
    public bool has_error { get; set; default = false; }

    public signal void updated ();

    private struct Step {
        public string text;
        public bool is_error;
    }

    private Step[] steps = {
        { "$ terraform init\nInitializing provider plugins...\nTerraform has been successfully initialized!", false },
        { "$ terraform plan\nPlan: 3 to add, 0 to change, 0 to destroy.", false },
        { "$ terraform apply -auto-approve\nhcloud_server.myapp: Creating...\nhcloud_server.myapp: Creation complete after 12s [id=48291]", false },
        { "$ ssh root@116.203.xx.xx\nConnected to myapp-prod (Debian 13)", false },
        { "$ curl -fsSL rawenv.sh/install | sh\nrawenv v0.1.0 installed to /usr/local/bin/rawenv", false },
        { "$ rawenv init --from-toml rawenv.toml\nConfiguration loaded: 5 services", false },
        { "$ rawenv up\n✓ PostgreSQL started on :5432\n✓ Meilisearch started on :7700\n✗ Redis failed: port 6379 already in use (conflict with system redis-server)", true }
    };

    public MockDeployEngine () {
        logs = new GenericArray<DeployLogEntry> ();
    }

    public void start_deploy () {
        logs = new GenericArray<DeployLogEntry> ();
        progress = 0.0;
        is_running = true;
        has_error = false;
        updated ();
        run_step (0);
    }

    private void run_step (int idx) {
        GLib.Timeout.add (500, () => {
            var entry = new DeployLogEntry ();
            entry.text = steps[idx].text;
            entry.is_error = steps[idx].is_error;
            logs.add (entry);
            progress = (double)(idx + 1) / (double) steps.length;
            if (steps[idx].is_error) {
                has_error = true;
                is_running = false;
                updated ();
                return Source.REMOVE;
            }
            updated ();
            if (idx + 1 < steps.length) {
                run_step (idx + 1);
            } else {
                is_running = false;
                updated ();
            }
            return Source.REMOVE;
        });
    }

    public void apply_ai_fix () {
        has_error = false;
        is_running = true;
        updated ();
        GLib.Timeout.add (700, () => {
            var entry = new DeployLogEntry ();
            entry.text = "🤖 AI Fix: Stopping system redis-server, binding rawenv Redis to :6379\n✓ Redis started on :6379";
            entry.is_error = false;
            logs.add (entry);
            progress = 1.0;
            is_running = false;
            updated ();
            return Source.REMOVE;
        });
    }
}
