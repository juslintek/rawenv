public class Rawenv.DashboardViewModel : Object {
    private DataRepository repo;
    public GenericArray<Service> services { get; owned set; }
    public GenericArray<LogEntry> logs { get; owned set; }
    public int selected_tab { get; set; default = 0; }
    public string selected_service_name { get; set; default = ""; }

    public DashboardViewModel (DataRepository repo) {
        this.repo = repo;
        this.services = new GenericArray<Service> ();
        this.logs = new GenericArray<LogEntry> ();
    }

    public void load () {
        services = repo.get_services ();
        logs = repo.get_logs ();
        if (services.length > 0) {
            selected_service_name = services[0].name;
        }
        notify_property ("services");
        notify_property ("logs");
    }

    public int running_count () {
        int count = 0;
        for (uint i = 0; i < services.length; i++) {
            if (services[i].status == "running") count++;
        }
        return count;
    }
}
