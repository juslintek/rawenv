void test_ai_chat_load () {
    var repo = new Rawenv.MockDataRepository ();
    var provider = new Rawenv.MockAiProvider ();
    var vm = new Rawenv.AiChatViewModel (repo, provider);
    vm.load ();
    assert_true (vm.messages.length > 0);
}

void test_ai_chat_send () {
    var repo = new Rawenv.MockDataRepository ();
    var provider = new Rawenv.MockAiProvider ();
    var vm = new Rawenv.AiChatViewModel (repo, provider);
    vm.load ();
    var initial_count = vm.messages.length;
    vm.send ("Hello");
    assert_true (vm.messages.length == initial_count + 2);
    assert_true (vm.messages[vm.messages.length - 2].role == "user");
    assert_true (vm.messages[vm.messages.length - 1].role == "assistant");
}

void test_ai_chat_provider_autonomy () {
    var provider = new Rawenv.MockAiProvider ();
    assert_true (provider.autonomy_level == "suggest-only");
    provider.autonomy_level = "full-autonomous";
    assert_true (provider.autonomy_level == "full-autonomous");
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/ai_chat/load", test_ai_chat_load);
    Test.add_func ("/ai_chat/send", test_ai_chat_send);
    Test.add_func ("/ai_chat/provider_autonomy", test_ai_chat_provider_autonomy);
    return Test.run ();
}
