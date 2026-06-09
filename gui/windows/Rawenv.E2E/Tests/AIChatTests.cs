using OpenQA.Selenium.Appium.Windows;

namespace Rawenv.E2E.Tests;

[TestClass]
public class AIChatTests
{
    private static WindowsDriver<WindowsElement> _driver = null!;

    [ClassInitialize]
    public static void ClassInit(TestContext _)
    {
        _driver = TestSetup.CreateSession();
        _driver.FindElementByAccessibilityId("NavAIChat").Click();
    }

    [ClassCleanup]
    public static void ClassCleanup() => _driver?.Quit();

    [TestMethod]
    public void AIChat_Messages_AreDisplayed()
    {
        var messages = _driver.FindElementByAccessibilityId("AIChatMessages");
        Assert.IsNotNull(messages);
        Assert.IsTrue(messages.Displayed);
    }

    [TestMethod]
    public void AIChat_SendButton_Exists()
    {
        var btn = _driver.FindElementByAccessibilityId("AIChatSendButton");
        Assert.IsNotNull(btn);
    }

    [TestMethod]
    public void AIChat_Input_AcceptsText()
    {
        var input = _driver.FindElementByAccessibilityId("AIChatInput");
        input.SendKeys("Test message");
        Assert.IsTrue(input.Text.Contains("Test message"));
    }
}
