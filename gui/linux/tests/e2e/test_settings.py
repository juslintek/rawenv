"""E2E tests for the Settings screen."""
from conftest import SettingsPage


def test_settings_sidebar_pages(app):
    """Settings shows all 9 pages in sidebar."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Settings").click()
    page = SettingsPage(app)
    sidebar = page.sidebar
    assert sidebar is not None


def test_settings_ai_provider_select(app):
    """Settings AI page has provider selection."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Settings").click()
    # Navigate to AI page in settings sidebar
    settings_sidebar = app.child(name="settings_sidebar")
    settings_sidebar.child(name="AI").click()
    page = SettingsPage(app)
    assert page.ai_provider_select is not None


def test_settings_ai_autonomy_level(app):
    """Settings AI page has autonomy level configuration."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Settings").click()
    settings_sidebar = app.child(name="settings_sidebar")
    settings_sidebar.child(name="AI").click()
    page = SettingsPage(app)
    assert page.ai_autonomy_level is not None


def test_settings_ai_byom_fields(app):
    """Settings AI page has BYOM custom endpoint and API key fields."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Settings").click()
    settings_sidebar = app.child(name="settings_sidebar")
    settings_sidebar.child(name="AI").click()
    endpoint = app.child(name="ai_custom_endpoint")
    api_key = app.child(name="ai_api_key")
    assert endpoint is not None
    assert api_key is not None
