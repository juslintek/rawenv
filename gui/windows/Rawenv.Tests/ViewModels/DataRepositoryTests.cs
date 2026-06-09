using Microsoft.VisualStudio.TestTools.UnitTesting;
using Rawenv.Services;
using Rawenv.Models;

namespace Rawenv.Tests.ViewModels;

[TestClass]
public class DataRepositoryTests
{
    [TestMethod]
    public void LoadServices_Returns5Services()
    {
        var repo = new MockDataRepository();
        var services = repo.FetchServicesAsync().Result;
        Assert.AreEqual(5, services.Count);
    }

    [TestMethod]
    public void LoadServices_FirstIsPostgreSQL()
    {
        var repo = new MockDataRepository();
        var services = repo.FetchServicesAsync().Result;
        Assert.AreEqual("PostgreSQL", services[0].Name);
    }

    [TestMethod]
    public void LoadServices_HasRunningAndStopped()
    {
        var repo = new MockDataRepository();
        var services = repo.FetchServicesAsync().Result;
        Assert.IsTrue(services.Any(s => s.Status == "running"));
        Assert.IsTrue(services.Any(s => s.Status == "stopped"));
    }

    [TestMethod]
    public void LoadLogs_Returns8Entries()
    {
        var repo = new MockDataRepository();
        var logs = repo.FetchLogsAsync().Result;
        Assert.AreEqual(8, logs.Count);
    }

    [TestMethod]
    public void LoadConnections_Returns4Entries()
    {
        var repo = new MockDataRepository();
        var connections = repo.FetchConnectionsAsync().Result;
        Assert.AreEqual(4, connections.Count);
    }

    [TestMethod]
    public void LoadProjects_Returns8Projects()
    {
        var repo = new MockDataRepository();
        var projects = repo.FetchProjectsAsync().Result;
        Assert.AreEqual(8, projects.Count);
    }

    [TestMethod]
    public void AIProvider_ReturnsResponse()
    {
        var ai = new MockAIProvider();
        var response = ai.SendAsync("hello").Result;
        Assert.IsFalse(string.IsNullOrEmpty(response));
    }
}
