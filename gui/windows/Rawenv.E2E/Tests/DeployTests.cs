using OpenQA.Selenium.Appium.Windows;

namespace Rawenv.E2E.Tests;

[TestClass]
public class DeployTests
{
    private static WindowsDriver<WindowsElement> _driver = null!;

    [ClassInitialize]
    public static void ClassInit(TestContext _)
    {
        _driver = TestSetup.CreateSession();
        _driver.FindElementByAccessibilityId("NavDeploy").Click();
    }

    [ClassCleanup]
    public static void ClassCleanup() => _driver?.Quit();

    [TestMethod]
    public void Deploy_Title_IsDisplayed()
    {
        var title = _driver.FindElementByAccessibilityId("DeployTitle");
        Assert.IsNotNull(title);
        Assert.AreEqual("Deploy", title.Text);
    }

    [TestMethod]
    public void Deploy_Tabs_ArePresent()
    {
        var tabs = _driver.FindElementByAccessibilityId("DeployTabs");
        Assert.IsNotNull(tabs);
    }

    [TestMethod]
    public void Deploy_TerraformContent_IsDisplayed()
    {
        var content = _driver.FindElementByAccessibilityId("TerraformContent");
        Assert.IsNotNull(content);
        Assert.IsTrue(content.Text.Length > 0);
    }
}
