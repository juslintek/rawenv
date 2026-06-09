public class Rawenv.ConnectionsViewModel : Object {
    private DataRepository repo;
    public GenericArray<Connection> connections { get; owned set; }

    public ConnectionsViewModel (DataRepository repo) {
        this.repo = repo;
        this.connections = new GenericArray<Connection> ();
    }

    public void load () {
        connections = repo.get_connections ();
        notify_property ("connections");
    }

    public int local_count () {
        int count = 0;
        for (uint i = 0; i < connections.length; i++) {
            if (connections[i].mode == "local") count++;
        }
        return count;
    }
}
