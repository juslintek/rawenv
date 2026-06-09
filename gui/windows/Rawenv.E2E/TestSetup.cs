using OpenQA.Selenium.Appium;
using OpenQA.Selenium.Appium.Windows;

namespace Rawenv.E2E;

public static class TestSetup
{
    private const string WinAppDriverUrl = "http://127.0.0.1:4723";
    private const string AppId = "Rawenv_rawenv!App";

    public static WindowsDriver<WindowsElement> CreateSession()
    {
        var options = new AppiumOptions();
        options.AddAdditionalCapability("app", AppId);
        options.AddAdditionalCapability("deviceName", "WindowsPC");
        return new WindowsDriver<WindowsElement>(new Uri(WinAppDriverUrl), options);
    }
}
