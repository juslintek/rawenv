public interface Rawenv.DataRepository : Object {
    public abstract GenericArray<Service> get_services ();
    public abstract GenericArray<LogEntry> get_logs ();
    public abstract GenericArray<AiMessage> get_ai_messages ();
    public abstract GenericArray<Connection> get_connections ();
    public abstract GenericArray<Project> get_projects ();
    public abstract Settings get_settings ();
    public abstract string get_deploy_terraform ();
    public abstract string get_deploy_ansible ();
    public abstract string get_deploy_containerfile ();
}
