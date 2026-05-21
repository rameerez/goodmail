# frozen_string_literal: true

require "test_helper"

# Tests for `Goodmail::Layout` — the ERB renderer that takes a body fragment
# from `Goodmail::Builder` and stitches it into the responsive table-based
# email skeleton at `lib/goodmail/layout.erb`.
class LayoutTest < Minitest::Test
  def test_default_layout_path_constant_points_at_the_shipped_template
    path = Goodmail::Layout::DEFAULT_LAYOUT_PATH
    assert File.file?(path), "DEFAULT_LAYOUT_PATH should resolve to a real file"
    assert path.end_with?("/lib/goodmail/layout.erb")
  end

  def test_render_returns_a_complete_html_document
    html = Goodmail::Layout.render("<p>Body</p>", "My Subject")
    assert html.start_with?("<!DOCTYPE html>")
    assert html.include?("<html")
    assert html.include?("</html>")
  end

  def test_render_injects_the_body_fragment_into_the_main_content_area
    body = "<p data-marker=\"unique-body-marker\">Hello</p>"
    html = Goodmail::Layout.render(body, "Subject")
    assert_includes html, body
  end

  def test_render_uses_subject_in_the_title_tag
    html = Goodmail::Layout.render("<p>x</p>", "Hello World")
    assert_match(/<title>Hello World<\/title>/, html)
  end

  def test_render_falls_back_to_empty_subject_when_nil
    html = Goodmail::Layout.render("<p>x</p>", nil)
    assert_match(/<title><\/title>/, html)
  end

  def test_render_normalizes_falsy_subject_to_an_empty_string_in_the_title
    # The layout's `subject || ""` chain folds nil AND false into an empty
    # title rather than emitting "false" as a literal title — much nicer
    # behavior for callers passing through indeterminate subject sources.
    html = Goodmail::Layout.render("<p>x</p>", false)
    assert_match(/<title><\/title>/, html)
  end

  def test_render_emits_the_preheader_when_one_is_passed
    html = Goodmail::Layout.render("<p>x</p>", "Subj", preheader: "secret preview text")
    assert_includes html, "secret preview text"
  end

  def test_render_falls_back_to_subject_for_preheader_when_none_passed
    # The hidden preheader span uses `preheader || subject` in the template,
    # so passing `subject` alone still gives us inbox preview text.
    html = Goodmail::Layout.render("<p>x</p>", "fallback subject")
    # The subject appears in <title> AND in the hidden preheader span.
    assert_operator html.scan("fallback subject").length, :>=, 2
  end

  def test_render_renders_the_logo_when_logo_url_is_configured
    GoodmailTestConfig.configure(
      logo_url: "https://cdn.example.com/logo.png",
      company_url: "https://example.com",
      company_name: "Acme"
    )
    html = Goodmail::Layout.render("<p>x</p>", "Subj")
    assert_includes html, 'src="https://cdn.example.com/logo.png"'
    assert_includes html, 'alt="Acme Logo"'
    assert_includes html, 'href="https://example.com"'
  end

  def test_render_renders_the_logo_unlinked_when_company_url_is_blank
    GoodmailTestConfig.configure(
      logo_url: "https://cdn.example.com/logo.png",
      company_url: nil,
      company_name: "Acme"
    )
    html = Goodmail::Layout.render("<p>x</p>", "Subj")
    assert_includes html, 'src="https://cdn.example.com/logo.png"'
    refute_match(/<a [^>]*href="[^"]*"[^>]*>\s*<img[^>]+cdn\.example\.com\/logo\.png/, html)
  end

  def test_render_omits_the_logo_block_entirely_when_logo_url_is_nil
    GoodmailTestConfig.configure(logo_url: nil, company_url: nil)
    html = Goodmail::Layout.render("<p>x</p>", "Subj")
    refute_match(/class="header"/, html)
  end

  def test_render_renders_the_footer_text_when_configured
    GoodmailTestConfig.configure(footer_text: "You signed up for the newsletter.")
    html = Goodmail::Layout.render("<p>x</p>", "Subj")
    assert_includes html, "You signed up for the newsletter."
  end

  def test_render_renders_an_unsubscribe_link_when_url_passed_and_show_flag_on
    GoodmailTestConfig.configure(
      show_footer_unsubscribe_link: true,
      footer_unsubscribe_link_text: "Unsubscribe me"
    )
    html = Goodmail::Layout.render(
      "<p>x</p>", "Subj",
      unsubscribe_url: "https://example.com/unsubscribe?u=42"
    )
    assert_includes html, 'href="https://example.com/unsubscribe?u=42"'
    assert_includes html, "Unsubscribe me"
  end

  def test_render_omits_the_unsubscribe_link_when_show_flag_off
    GoodmailTestConfig.configure(show_footer_unsubscribe_link: false)
    html = Goodmail::Layout.render(
      "<p>x</p>", "Subj",
      unsubscribe_url: "https://example.com/unsubscribe?u=42"
    )
    refute_includes html, 'href="https://example.com/unsubscribe?u=42"'
  end

  def test_render_omits_the_unsubscribe_link_when_show_flag_on_but_url_blank
    GoodmailTestConfig.configure(show_footer_unsubscribe_link: true)
    html = Goodmail::Layout.render("<p>x</p>", "Subj", unsubscribe_url: nil)
    refute_match(/footer_unsubscribe_link_text/, html)
  end

  def test_render_uses_brand_color_in_the_link_styling
    GoodmailTestConfig.configure(brand_color: "#abcdef")
    html = Goodmail::Layout.render("<p>x</p>", "Subj")
    assert_includes html, "color: #abcdef"
  end

  def test_render_uses_brand_color_for_the_button_fill
    GoodmailTestConfig.configure(brand_color: "#abcdef")
    html = Goodmail::Layout.render("<p>x</p>", "Subj")
    assert_includes html, "background-color: #abcdef"
  end

  def test_render_includes_company_name_in_the_footer_copyright
    GoodmailTestConfig.configure(company_name: "Acme Inc.")
    html = Goodmail::Layout.render("<p>x</p>", "Subj")
    assert_match(/&copy; \d{4} Acme Inc\./, html)
  end

  def test_render_accepts_a_custom_layout_path
    Tempfile.create(["custom_layout", ".erb"]) do |f|
      f.write("CUSTOM[<%= subject %>][<%= body_html %>]")
      f.flush
      html = Goodmail::Layout.render("<p>BODY</p>", "SUBJ", layout_path: f.path)
      assert_equal "CUSTOM[SUBJ][<p>BODY</p>]", html
    end
  end

  def test_render_raises_Goodmail_Error_when_template_is_missing
    error = assert_raises(Goodmail::Error) do
      Goodmail::Layout.render("<p>x</p>", "Subj", layout_path: "/tmp/nonexistent-#{SecureRandom.hex(8)}.erb")
    end
    assert_match(/Layout template not found/, error.message)
  end

  def test_render_wraps_arbitrary_ERB_failures_in_Goodmail_Error
    Tempfile.create(["broken_layout", ".erb"]) do |f|
      f.write("<%= raise 'erb-side boom' %>")
      f.flush
      error = assert_raises(Goodmail::Error) do
        Goodmail::Layout.render("<p>x</p>", "Subj", layout_path: f.path)
      end
      assert_match(/Failed to render layout template.*erb-side boom/, error.message)
    end
  end

  def test_render_does_not_html_escape_the_body_html
    # `body_html` is interpolated via `<%= %>` which is escape-by-default in
    # Rails-style ERB but plain pass-through in stdlib ERB. Goodmail uses
    # stdlib ERB here on purpose: the body comes from the trusted Builder
    # output (which DID escape user input at the DSL boundary), and we
    # need <table> / <tr> / etc. to land verbatim in the document.
    body = '<table role="x"><tr><td>cell</td></tr></table>'
    html = Goodmail::Layout.render(body, "Subj")
    assert_includes html, body
    refute_includes html, "&lt;table"
  end
end

require "tempfile"
require "securerandom"
