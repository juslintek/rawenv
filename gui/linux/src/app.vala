public class Rawenv.App : Adw.Application {
    public App () {
        Object (
            application_id: "dev.rawenv.gui",
            flags: ApplicationFlags.FLAGS_NONE
        );
    }

    protected override void activate () {
        load_css ();
        var win = new MainWindow (this);
        win.present ();
    }

    private void load_css () {
        var provider = new Gtk.CssProvider ();
        string[] paths = {
            "src/style.css",
            "../src/style.css",
            "/usr/share/rawenv-gui/style.css"
        };
        foreach (var p in paths) {
            if (FileUtils.test (p, FileTest.EXISTS)) {
                provider.load_from_path (p);
                Gtk.StyleContext.add_provider_for_display (
                    Gdk.Display.get_default (),
                    provider,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );
                return;
            }
        }
        // Fallback: load from resource-relative path
        provider.load_from_path ("style.css");
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    public static int main (string[] args) {
        var app = new App ();
        return app.run (args);
    }
}
