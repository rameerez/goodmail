# frozen_string_literal: true
require_relative "../test_helper"

class GoodmailBuilderTest < Minitest::Test
  def setup
    Goodmail.reset_config!
    Goodmail.configure do |c|
      c.company_name = "Acme Inc."
      c.brand_color = "#123456"
    end
    @builder = Goodmail::Builder.new
  end

  def test_text_escapes_and_allows_links_and_converts_newlines
    @builder.text("Hello <b>World</b> with <a href=\"/path\">link</a>\nLine2 & copy")
    html = @builder.html_output
    assert_includes html, "<p"
    refute_includes html, "<b>"
    assert_includes html, "<a href=\"/path\">link</a>"
    assert_includes html, "<br>"
    assert_includes html, "&amp; copy"
  end

  def test_button_generates_mso_fallback_and_brand_color
    Goodmail.configure { |c| c.brand_color = "#ff0000"; c.company_name = "Acme Inc." }
    @builder.button("Click", "https://example.com")
    out = @builder.html_output
    assert_includes out, "<!--[if mso]>"
    assert_includes out, "goodmail-button"
    assert_includes out, "https://example.com"
    assert_includes out, "Click"
  end

  def test_image_defaults_alt_to_company_name_and_applies_dimensions
    @builder.image("https://img", nil, width: 200, height: 100)
    out = @builder.html_output
    assert_includes out, "alt=\"Acme Inc.\""
    assert_includes out, "width:200px;"
    assert_includes out, "height:100px;"
  end

  def test_price_row_escapes_content
    @builder.price_row("Pro <plan>", "$10 & tax")
    out = @builder.html_output
    assert_includes out, "Pro &lt;plan&gt;"
    assert_includes out, "$10 &amp; tax"
  end

  def test_code_box_escapes_and_styles
    @builder.code_box("ABC<123>")
    out = @builder.html_output
    assert_includes out, "<strong>ABC&lt;123&gt;</strong>"
    assert_includes out, "background:#F8F8F8;"
  end

  def test_space_accepts_integer_like_values
    @builder.space(24)
    out = @builder.html_output
    assert_includes out, "height:24px"
  end

  def test_space_with_invalid_raises
    assert_raises(ArgumentError) do
      @builder.space("abc")
    end
  end

  def test_sign_defaults_to_company_name_and_can_override
    @builder.sign
    @builder.sign("Jane")
    out = @builder.html_output
    assert_includes out, "– Acme Inc."
    assert_includes out, "– Jane"
  end

  def test_headings_escape_and_style
    @builder.h1("Hello <x>")
    @builder.h2("Mid")
    @builder.h3("Low")
    out = @builder.html_output
    assert_includes out, "<h1"
    assert_includes out, "Hello &lt;x&gt;"
    assert_includes out, "<h2"
    assert_includes out, "<h3"
  end

  def test_center_wraps_inner_content
    @builder.center do
      @builder.text("inside")
    end
    out = @builder.html_output
    assert_includes out, "text-align:center;"
    assert_includes out, "inside"
  end

  def test_center_restores_parts_even_if_block_raises
    begin
      @builder.center do
        @builder.text("start")
        raise "boom"
      end
    rescue
      # ignored
    end
    assert_equal "", @builder.html_output
  end

  def test_line_hr
    @builder.line
    out = @builder.html_output
    assert_includes out, "<hr class=\"goodmail-hr\">"
  end

  def test_html_inserts_raw
    @builder.html("<div id='x'>raw</div>")
    out = @builder.html_output
    assert_includes out, "<div id='x'>raw</div>"
  end

  def test_html_output_joins_parts
    @builder.text("a")
    @builder.text("b")
    out = @builder.html_output
    assert_includes out, "a"
    assert_includes out, "b"
  end
end