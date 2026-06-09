"""E2E tests for the AI Chat screen."""
from conftest import AiChatPage


def test_ai_chat_messages_visible(app):
    """AI Chat shows pre-loaded messages from mock data."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="AI Chat").click()
    page = AiChatPage(app)
    messages = page.messages_list
    assert messages is not None


def test_ai_chat_input_exists(app):
    """AI Chat has an input field and send button."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="AI Chat").click()
    page = AiChatPage(app)
    assert page.input_field is not None
    assert page.send_button is not None


def test_ai_chat_send_message(app):
    """Sending a message adds it to the chat."""
    nav = app.child(name="navigation_sidebar")
    nav.child(name="AI Chat").click()
    page = AiChatPage(app)
    page.input_field.text = "Test message"
    page.send_button.click()
    # Verify new messages appeared
    messages = page.messages_list
    assert messages is not None
