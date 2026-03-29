# frozen_string_literal: true
require_relative "../test_helper"

class GoodmailEmailTest < Minitest::Test
  def setup
    Goodmail.reset_config!
    Goodmail.configure do |c|
      c.company_name = "Acme Inc."
      c.brand_color = "#123456"
      c.logo_url = nil
      c.company_url = nil
      c.unsubscribe_url = nil
      c.default_preheader = nil
      c.footer_text = nil
      c.show_footer_unsubscribe_link = false
    end
  end

  def test_render_returns_email_parts_with_html_and_text
    parts = Goodmail.render(subject: "Hello") do
      h1 "Hi"
      text "Line1\nLine2"
      button "Go", "https://example.com"
    end
    assert_kind_of Goodmail::EmailParts, parts
    # Heading includes inline styles applied by Builder
    assert_includes parts.html, ">Hi</h1>"
    assert_includes parts.text, "Line1"
    assert_includes parts.text, "Line2"
  end

  def test_render_uses_headers_over_config_for_unsubscribe_and_preheader
    Goodmail.configure do |c|
      c.unsubscribe_url = "https://global-unsub"
      c.default_preheader = "Global"
    end
    parts = Goodmail.render({ subject: "S", unsubscribe_url: "https://per", preheader: "Per" }) do
      text "Body"
    end
    assert_includes parts.html, ">\n  Per\n</span>"
    # Unsubscribe footer link appears only when both config flag and url set; it's at layout stage.
    Goodmail.configure { |c| c.show_footer_unsubscribe_link = true }
    parts2 = Goodmail.render({ subject: "S2", unsubscribe_url: "https://per2", preheader: "Per2" }) { text "Body" }
    assert_includes parts2.html, "href=\"https://per2\""
  end

  def test_plaintext_cleanup_removes_logo_and_urls_and_compacts_blank_lines
    Goodmail.configure do |c|
      c.logo_url = "https://cdn/logo.png"
      c.company_url = "https://company.example"
      c.company_name = "Acme Inc."
    end
    parts = Goodmail.render(subject: "S") do
      # include an image which may produce URL-only lines in plaintext
      image "https://cdn/logo.png", "Acme Inc. Logo", width: 20
      text "Hello\n\n\nWorld"
    end
    # The URL-only line should be stripped and extra newlines compacted
    refute_match(/^\s*https?:\/\//i, parts.text)
    # Depending on plaintext conversion, the alt text may appear; our cleanup targets specific patterns.
    # Ensure excessive blank lines were compacted.
    refute_includes parts.text, "\n\n\n"
    assert_includes parts.text, "Hello"
    assert_includes parts.text, "World"
  end
end