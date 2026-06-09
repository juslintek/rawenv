public class Rawenv.DeployViewModel : Object {
    private DataRepository repo;
    public string terraform { get; set; default = ""; }
    public string ansible { get; set; default = ""; }
    public string containerfile { get; set; default = ""; }
    public int selected_tab { get; set; default = 0; }

    public DeployViewModel (DataRepository repo) {
        this.repo = repo;
    }

    public void load () {
        terraform = repo.get_deploy_terraform ();
        ansible = repo.get_deploy_ansible ();
        containerfile = repo.get_deploy_containerfile ();
    }
}
