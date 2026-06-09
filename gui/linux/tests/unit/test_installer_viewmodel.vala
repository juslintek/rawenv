void test_installer_initial_state () {
    var vm = new Rawenv.InstallerViewModel ();
    assert_true (vm.current_step == 0);
    assert_true (vm.platform_name == "Linux");
}

void test_installer_next_step () {
    var vm = new Rawenv.InstallerViewModel ();
    vm.next_step ();
    assert_true (vm.current_step == 1);
    vm.next_step ();
    assert_true (vm.current_step == 2);
    vm.next_step ();
    assert_true (vm.current_step == 2); // stays at last
}

void test_installer_prev_step () {
    var vm = new Rawenv.InstallerViewModel ();
    vm.next_step ();
    vm.next_step ();
    vm.prev_step ();
    assert_true (vm.current_step == 1);
    vm.prev_step ();
    assert_true (vm.current_step == 0);
    vm.prev_step ();
    assert_true (vm.current_step == 0); // stays at first
}

void test_installer_is_last () {
    var vm = new Rawenv.InstallerViewModel ();
    assert_false (vm.is_last_step ());
    vm.next_step ();
    vm.next_step ();
    assert_true (vm.is_last_step ());
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/installer/initial_state", test_installer_initial_state);
    Test.add_func ("/installer/next_step", test_installer_next_step);
    Test.add_func ("/installer/prev_step", test_installer_prev_step);
    Test.add_func ("/installer/is_last", test_installer_is_last);
    return Test.run ();
}
