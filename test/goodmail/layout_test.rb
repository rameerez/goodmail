# frozen_string_literal: true
require_relative "../test_helper"

class GoodmailLayoutTest < Minitest::Test
  def setup
    Goodmail.reset_config!
    Goodmail.configure do |c|
      c.company_name = "Acme Inc."
      c.brand_color = "#123456"
      c.logo_url = nil
      c.company_url = nil
      c.footer_text = nil
      c.show_footer_unsubscribe_link = false
    end
  end

  def test_render_includes_subject_in_title_and_schema
    html = Goodmail::Layout.render("<p>Body</p>", "Subject X")
    assert_includes html, "<title>Subject X</title>"
    assert_includes html, "itemprop=\"name\" content=\"Subject X\""
  end

  def test_render_includes_preheader_when_provided
    html = Goodmail::Layout.render("<p>Body</p>", "S", preheader: "Preview here")
    assert_includes html, ">\n  Preview here\n</span>"
  end

  def test_render_no_logo_section_when_logo_not_set
    html = Goodmail::Layout.render("<p>Body</p>", "S")
    refute_includes html, "alt=\"Acme Inc. Logo\""
  end

  def test_render_logo_with_link_when_company_url_present
    Goodmail.configure do |c|
      c.logo_url = "https://cdn/logo.png"
      c.company_url = "https://company.example"
    end
    html = Goodmail::Layout.render("<p>Body</p>", "S")
    assert_includes html, "href=\"https://company.example\""
    assert_includes html, "src=\"https://cdn/logo.png\""
    assert_includes html, "Acme Inc. Logo"
  end

  def test_render_footer_text_and_unsubscribe_link
    Goodmail.configure do |c|
      c.footer_text = "Why you got this"
      c.show_footer_unsubscribe_link = true
    end
    html = Goodmail::Layout.render("<p>Body</p>", "S", unsubscribe_url: "https://unsubscribe")
    assert_includes html, "Why you got this"
    assert_includes html, "href=\"https://unsubscribe\""
  end

  def test_missing_template_raises_goodmail_error
    error = assert_raises(Goodmail::Error) do
      Goodmail::Layout.render("", "S", layout_path: File.expand_path("missing.erb", Dir.tmpdir))
    end
    assert_includes error.message, "Layout template not found"
  end
end