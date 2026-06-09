void test_settings_load () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.SettingsViewModel (repo);
    vm.load ();
    assert_true (vm.settings.store_location.length > 0);
    assert_true (vm.settings.ai_provider.length > 0);
}

void test_settings_is_byom () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.SettingsViewModel (repo);
    vm.load ();
    assert_false (vm.is_byom ());
    vm.settings.ai_provider = "Custom OpenAI-compatible";
    assert_true (vm.is_byom ());
}

void test_settings_providers_list () {
    var repo = new Rawenv.MockDataRepository ();
    var vm = new Rawenv.SettingsViewModel (repo);
    assert_true (vm.ai_providers.length == 8);
    assert_true (vm.autonomy_levels.length == 4);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/settings/load", test_settings_load);
    Test.add_func ("/settings/is_byom", test_settings_is_byom);
    Test.add_func ("/settings/providers_list", test_settings_providers_list);
    return Test.run ();
}
