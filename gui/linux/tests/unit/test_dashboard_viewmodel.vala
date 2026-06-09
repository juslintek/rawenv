void test_dashboard_load () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.DashboardViewModel (repo);
    vm.load ();
    assert_true (vm.services.length > 0);
    assert_true (vm.logs.length > 0);
}

void test_dashboard_running_count () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.DashboardViewModel (repo);
    vm.load ();
    assert_true (vm.running_count () >= 0);
    assert_true (vm.running_count () <= (int) vm.services.length);
}

void test_dashboard_selected_service () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.DashboardViewModel (repo);
    vm.load ();
    if (vm.services.length > 0) {
        assert_true (vm.selected_service_name == vm.services[0].name);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/dashboard/load", test_dashboard_load);
    Test.add_func ("/dashboard/running_count", test_dashboard_running_count);
    Test.add_func ("/dashboard/selected_service", test_dashboard_selected_service);
    return Test.run ();
}
