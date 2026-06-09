void test_connections_load () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.ConnectionsViewModel (repo);
    vm.load ();
    assert_true (vm.connections.length > 0);
}

void test_connections_local_count () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.ConnectionsViewModel (repo);
    vm.load ();
    assert_true (vm.local_count () >= 0);
    assert_true (vm.local_count () <= (int) vm.connections.length);
}

void test_connections_env_vars () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.ConnectionsViewModel (repo);
    vm.load ();
    assert_true (vm.connections[0].env_var.length > 0);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/connections/load", test_connections_load);
    Test.add_func ("/connections/local_count", test_connections_local_count);
    Test.add_func ("/connections/env_vars", test_connections_env_vars);
    return Test.run ();
}
