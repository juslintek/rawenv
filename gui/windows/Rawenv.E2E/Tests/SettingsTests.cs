using OpenQA.Selenium.Appium.Windows;

namespace Rawenv.E2E.Tests;

[TestClass]
public class SettingsTests
{
    private static WindowsDriver<WindowsElement> _driver = null!;

    [ClassInitialize]
    public static void ClassInit(TestContext _)
    {
        _driver = TestSetup.CreateSession();
        _driver.FindElementByAccessibilityId("NavSettings").Click();
    }

    [ClassCleanup]
    public static void ClassCleanup() => _driver?.Quit();

    [TestMethod]
    public void Settings_Title_IsDisplayed()
    {
        var title = _driver.FindElementByAccessibilityId("SettingsTitle");
        Assert.IsNotNull(title);
        Assert.AreEqual("Settings", title.Text);
    }

    [TestMethod]
    public void Settings_AIProvider_ComboExists()
    {
        var combo = _driver.FindElementByAccessibilityId("ComboAIProvider");
        Assert.IsNotNull(combo);
    }

    [TestMethod]
    public void Settings_CustomEndpoint_Exists()
    {
        var field = _driver.FindElementByAccessibilityId("TextCustomEndpoint");
        Assert.IsNotNull(field);
    }

    [TestMethod]
    public void Settings_AutonomyLevel_ComboExists()
    {
        var combo = _driver.FindElementByAccessibilityId("ComboAutonomy");
        Assert.IsNotNull(combo);
    }
}
