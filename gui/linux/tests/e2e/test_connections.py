"""E2E tests for the Connections screen."""
from conftest import ConnectionsPage


def test_connections_list_visible(app):
    """Connections screen shows the connection list."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Connections").click()
    page = ConnectionsPage(app)
    assert page.connections_list is not None


def test_connections_env_vars_shown(app):
    """Connections screen shows environment variable names."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Connections").click()
    # Check DATABASE_URL connection exists
    conn = app.child(name="connection_DATABASE_URL")
    assert conn is not None


def test_connections_redis_shown(app):
    """Connections screen shows REDIS_URL connection."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Connections").click()
    conn = app.child(name="connection_REDIS_URL")
    assert conn is not None
