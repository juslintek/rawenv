public interface Rawenv.NavigationService : Object {
    public abstract void navigate_to (string destination);
    public abstract void go_back ();
    public signal void navigation_changed (string destination);
}
