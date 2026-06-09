public class Rawenv.MockServiceManager : Object {
    private DataRepository repo;
    public GenericArray<Service> services { get; owned set; }

    public signal void services_changed ();

    public MockServiceManager (DataRepository repo) {
        this.repo = repo;
        this.services = repo.get_services ();
    }

    public void start_service (string name) {
        for (uint i = 0; i < services.length; i++) {
            if (services[i].name == name) {
                services[i].status = "running";
                services[i].pid = Random.int_range (10000, 65000);
                services[i].cpu = "0.1%";
                services[i].mem = "8MB";
                services[i].uptime = "0s";
                services_changed ();
                notify_property ("services");
                return;
            }
        }
    }

    public void stop_service (string name) {
        for (uint i = 0; i < services.length; i++) {
            if (services[i].name == name) {
                services[i].status = "stopped";
                services[i].pid = 0;
                services[i].cpu = "";
                services[i].mem = "";
                services[i].uptime = "";
                services_changed ();
                notify_property ("services");
                return;
            }
        }
    }

    public void restart_service (string name) {
        stop_service (name);
        GLib.Timeout.add (300, () => {
            start_service (name);
            return Source.REMOVE;
        });
    }

    public void start_all () {
        for (uint i = 0; i < services.length; i++) {
            if (services[i].status != "running") {
                start_service (services[i].name);
            }
        }
    }

    public void stop_all () {
        for (uint i = 0; i < services.length; i++) {
            if (services[i].status == "running") {
                stop_service (services[i].name);
            }
        }
    }

    public int running_count () {
        int count = 0;
        for (uint i = 0; i < services.length; i++) {
            if (services[i].status == "running") count++;
        }
        return count;
    }
}
