using OpenQA.Selenium.Appium.Windows;

namespace Rawenv.E2E.Tests;

[TestClass]
public class DashboardTests
{
    private static WindowsDriver<WindowsElement> _driver = null!;

    [ClassInitialize]
    public static void ClassInit(TestContext _) => _driver = TestSetup.CreateSession();

    [ClassCleanup]
    public static void ClassCleanup() => _driver?.Quit();

    [TestMethod]
    public void Dashboard_ServicesList_IsDisplayed()
    {
        var list = _driver.FindElementByAccessibilityId("DashboardServicesList");
        Assert.IsNotNull(list);
        Assert.IsTrue(list.Displayed);
    }

    [TestMethod]
    public void Dashboard_Tabs_ArePresent()
    {
        var tabs = _driver.FindElementByAccessibilityId("DashboardTabs");
        Assert.IsNotNull(tabs);
    }

    [TestMethod]
    public void Dashboard_Title_IsCorrect()
    {
        var title = _driver.FindElementByAccessibilityId("DashboardTitle");
        Assert.AreEqual("Dashboard", title.Text);
    }
}
