void test_deploy_load () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.DeployViewModel (repo);
    vm.load ();
    assert_true (vm.terraform.length > 0);
    assert_true (vm.ansible.length > 0);
    assert_true (vm.containerfile.length > 0);
}

void test_deploy_terraform_content () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.DeployViewModel (repo);
    vm.load ();
    assert_true (vm.terraform.contains ("hcloud_server"));
}

void test_deploy_tab_selection () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.DeployViewModel (repo);
    assert_true (vm.selected_tab == 0);
    vm.selected_tab = 2;
    assert_true (vm.selected_tab == 2);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/deploy/load", test_deploy_load);
    Test.add_func ("/deploy/terraform_content", test_deploy_terraform_content);
    Test.add_func ("/deploy/tab_selection", test_deploy_tab_selection);
    return Test.run ();
}
