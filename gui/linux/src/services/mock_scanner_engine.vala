public class Rawenv.ScanPath : Object {
    public string path { get; set; default = ""; }
    public string status { get; set; default = "queued"; }
    public int project_count { get; set; default = 0; }
    public bool cached { get; set; default = false; }
}

public class Rawenv.MockScannerEngine : Object {
    public GenericArray<ScanPath> paths { get; owned set; }
    public int total_projects { get; set; default = 8; }
    public bool is_scanning { get; set; default = false; }

    public signal void scan_updated ();

    public MockScannerEngine () {
        paths = new GenericArray<ScanPath> ();
        add_path ("~/Projects/", "done", 5, true);
        add_path ("~/Developer/", "done", 2, true);
        add_path ("~/Code/", "done", 1, false);
        add_path ("/Volumes/Projects/", "queued", 0, false);
        add_path ("~/Desktop/", "queued", 0, false);
        add_path ("~/Documents/", "queued", 0, false);
    }

    private void add_path (string p, string status, int count, bool cached) {
        var sp = new ScanPath ();
        sp.path = p;
        sp.status = status;
        sp.project_count = count;
        sp.cached = cached;
        paths.add (sp);
    }

    public void start_scan () {
        is_scanning = true;
        notify_property ("is_scanning");
        scan_updated ();
        scan_next (0);
    }

    private void scan_next (int idx) {
        if (idx >= (int) paths.length) {
            is_scanning = false;
            notify_property ("is_scanning");
            scan_updated ();
            return;
        }
        if (paths[idx].status != "queued") {
            scan_next (idx + 1);
            return;
        }
        paths[idx].status = "scanning";
        scan_updated ();
        GLib.Timeout.add (600, () => {
            int found = Random.int_range (1, 5);
            paths[idx].status = "done";
            paths[idx].project_count = found;
            total_projects += found;
            notify_property ("total_projects");
            scan_updated ();
            scan_next (idx + 1);
            return Source.REMOVE;
        });
    }
}
