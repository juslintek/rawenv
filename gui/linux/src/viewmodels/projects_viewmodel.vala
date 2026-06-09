public class Rawenv.ProjectsViewModel : Object {
    private DataRepository repo;
    public GenericArray<Project> projects { get; owned set; }
    public string search_query { get; set; default = ""; }

    public ProjectsViewModel (DataRepository repo) {
        this.repo = repo;
        this.projects = new GenericArray<Project> ();
    }

    public void load () {
        projects = repo.get_projects ();
        notify_property ("projects");
    }

    public GenericArray<Project> filtered_projects () {
        if (search_query == "") return projects;
        var filtered = new GenericArray<Project> ();
        for (uint i = 0; i < projects.length; i++) {
            if (projects[i].name.contains (search_query)) {
                filtered.add (projects[i]);
            }
        }
        return filtered;
    }
}
