"""E2E tests for the Deploy screen."""
from conftest import DeployPage


def test_deploy_tabs_visible(app):
    """Deploy screen shows Terraform, Ansible, Containerfile tabs."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Deploy").click()
    page = DeployPage(app)
    assert page.deploy_tabs is not None


def test_deploy_terraform_content(app):
    """Deploy screen shows Terraform configuration."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Deploy").click()
    tf = app.child(name="deploy_terraform")
    assert tf is not None


def test_deploy_apply_button(app):
    """Deploy screen has an apply/deploy button."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="Deploy").click()
    page = DeployPage(app)
    assert page.apply_button is not None
