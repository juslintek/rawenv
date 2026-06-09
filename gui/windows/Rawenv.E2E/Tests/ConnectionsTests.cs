using OpenQA.Selenium.Appium.Windows;

namespace Rawenv.E2E.Tests;

[TestClass]
public class ConnectionsTests
{
    private static WindowsDriver<WindowsElement> _driver = null!;

    [ClassInitialize]
    public static void ClassInit(TestContext _)
    {
        _driver = TestSetup.CreateSession();
        _driver.FindElementByAccessibilityId("NavConnections").Click();
    }

    [ClassCleanup]
    public static void ClassCleanup() => _driver?.Quit();

    [TestMethod]
    public void Connections_Title_IsDisplayed()
    {
        var title = _driver.FindElementByAccessibilityId("ConnectionsTitle");
        Assert.IsNotNull(title);
        Assert.AreEqual("Connections", title.Text);
    }

    [TestMethod]
    public void Connections_List_IsDisplayed()
    {
        var list = _driver.FindElementByAccessibilityId("ConnectionsList");
        Assert.IsNotNull(list);
        Assert.IsTrue(list.Displayed);
    }
}
