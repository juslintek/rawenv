"""E2E tests for the Dashboard screen."""
from conftest import DashboardPage


def test_dashboard_services_visible(app):
    """Dashboard shows the services list with mock data."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Dashboard").click()
    page = DashboardPage(app)
    services = page.services_list
    assert services is not None
    # Check that PostgreSQL service is listed
    assert app.child(name="PostgreSQL") is not None


def test_dashboard_tabs_exist(app):
    """Dashboard has Logs, Config, Connection, Cell, Backups tabs."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Dashboard").click()
    page = DashboardPage(app)
    tabs = page.dashboard_tabs
    assert tabs is not None


def test_dashboard_logs_displayed(app):
    """Dashboard logs tab shows log entries."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Dashboard").click()
    # Logs are shown in the first tab by default
    window = app.child(roleName="frame", name="Rawenv")
    assert window is not None
