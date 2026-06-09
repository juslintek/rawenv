public class Rawenv.MockInstallerEngine : Object {
    public enum State { WELCOME, INSTALLING, DONE }

    public State state { get; set; default = State.WELCOME; }
    public int current_step { get; set; default = 0; }
    public double progress { get; set; default = 0.0; }

    public signal void state_changed ();
    public signal void step_changed ();

    public string[] steps = {
        "Downloading binary…",
        "Installing rawenv…",
        "Registering service manager…",
        "Configuring isolation…",
        "Setting up DNS…",
        "Adding to PATH…"
    };

    public void start_install () {
        state = State.INSTALLING;
        current_step = 0;
        progress = 0.0;
        state_changed ();
        notify_property ("state");
        advance_step ();
    }

    private void advance_step () {
        GLib.Timeout.add (350, () => {
            current_step++;
            progress = (double) current_step / (double) steps.length;
            step_changed ();
            notify_property ("progress");
            notify_property ("current_step");
            if (current_step >= steps.length) {
                state = State.DONE;
                state_changed ();
                notify_property ("state");
                return Source.REMOVE;
            }
            advance_step ();
            return Source.REMOVE;
        });
    }
}
