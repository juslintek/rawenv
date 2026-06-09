void test_projects_load () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.ProjectsViewModel (repo);
    vm.load ();
    assert_true (vm.projects.length > 0);
}

void test_projects_filter () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.ProjectsViewModel (repo);
    vm.load ();
    vm.search_query = "rawenv";
    var filtered = vm.filtered_projects ();
    assert_true (filtered.length >= 1);
    assert_true (filtered[0].name == "rawenv");
}

void test_projects_filter_empty () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.ProjectsViewModel (repo);
    vm.load ();
    vm.search_query = "";
    var filtered = vm.filtered_projects ();
    assert_true (filtered.length == vm.projects.length);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/projects/load", test_projects_load);
    Test.add_func ("/projects/filter", test_projects_filter);
    Test.add_func ("/projects/filter_empty", test_projects_filter_empty);
    return Test.run ();
}
