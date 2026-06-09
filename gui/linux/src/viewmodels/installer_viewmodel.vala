public class Rawenv.InstallerViewModel : Object {
    public int current_step { get; set; default = 0; }
    public string[] steps = { "welcome", "install", "done" };
    public string platform_name { get; set; default = "Linux"; }
    public string platform_detail { get; set; default = "x86_64 · Debian 13"; }
    public string service_manager { get; set; default = "systemd"; }
    public string isolation { get; set; default = "Namespaces + Landlock"; }

    public void next_step () {
        if (current_step < steps.length - 1) {
            current_step++;
        }
    }

    public void prev_step () {
        if (current_step > 0) {
            current_step--;
        }
    }

    public bool is_last_step () {
        return current_step == steps.length - 1;
    }
}
