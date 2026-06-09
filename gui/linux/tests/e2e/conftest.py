"""Shared fixtures for rawenv GUI e2e tests using dogtail."""
import subprocess
import time
import pytest
from dogtail.tree import root
from dogtail import utils


APP_NAME = "rawenv-gui"
APP_PATH = "./build/rawenv-gui"


@pytest.fixture(scope="session", autouse=True)
def enable_a11y():
    """Enable accessibility for AT-SPI."""
    utils.enableA11y()


@pytest.fixture(scope="module")
def app():
    """Launch the application and return the dogtail root node."""
    proc = subprocess.Popen([APP_PATH], env={"DISPLAY": ":99", "GTK_A11Y": "atspi"})
    time.sleep(3)  # Wait for app to start
    try:
        app_node = root.application("rawenv-gui")
        yield app_node
    finally:
        proc.terminate()
        proc.wait(timeout=5)


class DashboardPage:
    def __init__(self, app):
        self.app = app
        self.window = app.child(roleName="frame", name="Rawenv")

    @property
    def services_list(self):
        return self.window.child(name="services_list")

    @property
    def dashboard_tabs(self):
        return self.window.child(name="dashboard_tabs")


class AiChatPage:
    def __init__(self, app):
        self.app = app
        self.window = app.child(roleName="frame", name="Rawenv")

    @property
    def messages_list(self):
        return self.window.child(name="ai_messages_list")

    @property
    def input_field(self):
        return self.window.child(name="ai_chat_input")

    @property
    def send_button(self):
        return self.window.child(name="ai_send_button")


class SettingsPage:
    def __init__(self, app):
        self.app = app
        self.window = app.child(roleName="frame", name="Rawenv")

    @property
    def sidebar(self):
        return self.window.child(name="settings_sidebar")

    @property
    def ai_provider_select(self):
        return self.window.child(name="ai_provider_select")

    @property
    def ai_autonomy_level(self):
        return self.window.child(name="ai_autonomy_level")


class ConnectionsPage:
    def __init__(self, app):
        self.app = app
        self.window = app.child(roleName="frame", name="Rawenv")

    @property
    def connections_list(self):
        return self.window.child(name="connections_list")


class DeployPage:
    def __init__(self, app):
        self.app = app
        self.window = app.child(roleName="frame", name="Rawenv")

    @property
    def deploy_tabs(self):
        return self.window.child(name="deploy_tabs")

    @property
    def apply_button(self):
        return self.window.child(name="deploy_apply_button")
