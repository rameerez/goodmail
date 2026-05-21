# frozen_string_literal: true

require "test_helper"

# Tests for `Goodmail::Plaintext` — the shared plaintext generator that
# both `Goodmail::Email.render` and `Goodmail::Mailer#compose_message`
# use to derive the `text/plain` part of every multipart message.
#
# Each branch in this file is a regression test for a real bug we
# observed in Mailcatcher and reproduced end-to-end:
#
#   1. Preheader leak — the layout's hidden-span inbox-preview text
#      was rendered as a phantom first line of the plaintext body
#      because Premailer's `to_plain_text` does not honor
#      `display: none`.
#   2. Button label duplication — `button` emits both a `<v:roundrect>`
#      (Outlook VML, inside `<!--[if mso]>...<![endif]-->`) AND a
#      regular `<a>`. Premailer ignores conditional comments and
#      extracted text from BOTH, so the label appeared twice in
#      plaintext (once bare, once with the URL).
#   3. Image alt leak — `image` / `inline_image` calls without an
#      explicit alt fall back to `config.company_name`. Premailer
#      extracted that alt verbatim into plaintext, so a stray
#      "CompanyName" line appeared next to every embedded image.
class PlaintextTest < Minitest::Test
  # ── Module surface ──────────────────────────────────────────────────

  def test_generate_returns_a_String
    text = Goodmail::Plaintext.generate(layout_html_with(text_body: "<p>Hi</p>"))
    assert_kind_of String, text
  end

  def test_generate_strips_trailing_and_leading_whitespace
    text = Goodmail::Plaintext.generate(layout_html_with(text_body: "<p>Hi</p>"))
    refute_match(/\A\s/, text)
    refute_match(/\s\z/, text)
  end

  def test_generate_compacts_runs_of_blank_lines_to_at_most_one
    # The cumulative gsubs upstream + Premailer's own line breaks can
    # leave 3+ consecutive newlines; we cap at 2 (one blank line).
    text = Goodmail::Plaintext.generate(layout_html_with(text_body: "<p>One</p><p>Two</p><p>Three</p>"))
    refute_match(/\n{3,}/, text)
  end

  # ── BUG #1: preheader leak ─────────────────────────────────────────

  def test_preheader_does_not_leak_into_plaintext_when_passed_explicitly
    html = compose_full_layout(preheader: "Secret inbox preview text", text_body: "<p>Hello body</p>")
    text = Goodmail::Plaintext.generate(html, preheader: "Secret inbox preview text")
    refute_includes text, "Secret inbox preview text",
                    "preheader should never appear in plaintext"
    assert_includes text, "Hello body"
  end

  def test_preheader_does_not_leak_when_caller_omits_explicit_preheader_arg
    # Even without telling `Goodmail::Plaintext` what the preheader
    # text was, the hidden-span signature (`display:none` +
    # `font-size:1px`) gets stripped from the source HTML so Premailer
    # never sees the text in the first place.
    html = compose_full_layout(preheader: "Sneaky preview text", text_body: "<p>Body</p>")
    text = Goodmail::Plaintext.generate(html)
    refute_includes text, "Sneaky preview text"
  end

  def test_preheader_text_in_visible_body_is_NOT_erased_when_it_is_a_legitimate_repetition
    # Conservative regex: we only strip the preheader from the LEADING
    # position. If a caller deliberately repeats the preheader text in
    # the visible body, that copy survives.
    html = <<~HTML
      <span style="display:none !important; font-size:1px;">Repeated</span>
      <body>
        <p>Body</p>
        <p>Repeated</p>
      </body>
    HTML
    text = Goodmail::Plaintext.generate(html, preheader: "Repeated")
    # The leading hidden-span occurrence is gone. The `<p>Repeated</p>`
    # in the visible body survives.
    occurrences = text.scan("Repeated").length
    assert_equal 1, occurrences
  end

  # ── BUG #2: button label duplication ───────────────────────────────

  def test_button_label_appears_exactly_once_in_plaintext
    # A `button` DSL call emits BOTH a VML `<v:roundrect>` (Outlook,
    # inside `<!--[if mso]>...<![endif]-->`) AND a plain `<a>` link.
    # Premailer ignores conditional comments and would normally
    # extract text from both — duplicating the label.
    html = layout_html_with(text_body: build_dsl { button "Open the receipt", "https://example.com/r" })
    text = Goodmail::Plaintext.generate(html)
    occurrences = text.scan("Open the receipt").length
    assert_equal 1, occurrences,
                 "button label should appear ONCE in plaintext (was: #{occurrences})\n#{text}"
  end

  def test_button_url_is_preserved_in_plaintext
    # The bare label without the URL is useless in plaintext (the
    # recipient can't click anything). Premailer's `to_plain_text`
    # renders `<a>` as `text ( url )` — that's the surviving rendering
    # we want.
    html = layout_html_with(text_body: build_dsl { button "Open the receipt", "https://example.com/r" })
    text = Goodmail::Plaintext.generate(html)
    assert_match(%r{Open the receipt\s*\(\s*https://example\.com/r\s*\)}, text)
  end

  def test_button_label_does_not_leak_through_when_embedded_inside_MSO_only_block_alone
    # Defensive: any literal `<v:roundrect>` block (with or without the
    # surrounding conditional comment) gets stripped before plaintext
    # extraction because the MSO conditional comment that wraps it is
    # always stripped. So the VML's inner `<center>label</center>`
    # doesn't get extracted twice.
    html = <<~HTML
      <body>
        <p>before</p>
        <!--[if mso]>
        <table><tr><td>
          <v:roundrect>
            <center>OUTLOOK_ONLY_LABEL</center>
          </v:roundrect>
        </td></tr></table>
        <![endif]-->
        <p>after</p>
      </body>
    HTML
    text = Goodmail::Plaintext.generate(html)
    refute_includes text, "OUTLOOK_ONLY_LABEL"
    assert_includes text, "before"
    assert_includes text, "after"
  end

  # ── BUG #3: company-name alt leak ──────────────────────────────────

  def test_company_name_alt_does_not_leak_as_a_standalone_plaintext_line
    GoodmailTestConfig.configure(company_name: "Acme")
    body = build_dsl do
      inline_image "hero.png", "PNG_BYTES" # no alt = falls back to company_name
      text "Body content."
      sign # adds "- Acme" — must survive cleanup
    end
    text = Goodmail::Plaintext.generate(compose_full_layout(text_body: body))
    # The bare standalone "Acme" line that the inline-image's alt
    # would otherwise extract to does NOT appear.
    refute_match(/^Acme$/, text)
    assert_includes text, "Body content."
    # The legit "– Acme" signature line and "© 2026 Acme" copyright
    # line — both of which include surrounding context — survive
    # cleanup intact (the regex only strips lines that are NOTHING
    # but the bare company name).
    assert_match(/–\s*Acme/, text)
    assert_match(/©\s*\d{4}\s*Acme/, text)
  end

  def test_company_name_inside_a_sentence_is_not_clobbered
    # Conservative cleanup: only standalone lines that EXACTLY match
    # the company name are stripped. If someone writes "Welcome to
    # Acme" the sentence survives untouched.
    GoodmailTestConfig.configure(company_name: "Acme")
    html = layout_html_with(text_body: "<p>Welcome to Acme, where we share rides.</p>")
    text = Goodmail::Plaintext.generate(html)
    assert_includes text, "Welcome to Acme, where we share rides."
  end

  # ── BUG already fixed before this round, regression-tested here ────

  def test_logo_alt_line_with_company_url_in_parens_is_stripped
    GoodmailTestConfig.configure(
      company_name: "Acme",
      company_url: "https://example.com",
      logo_url: "https://cdn.example.com/logo.png"
    )
    # Premailer extracts the layout's clickable header logo as
    #   "Acme Logo ( https://example.com )"
    # The cleanup regex specifically targets that shape.
    html = compose_full_layout(text_body: "<p>Body</p>")
    text = Goodmail::Plaintext.generate(html)
    refute_match(/Acme\s+Logo\s*\(.*example\.com.*\)/, text)
    assert_includes text, "Body"
  end

  # ── Standalone URL preservation ────────────────────────────────────

  def test_standalone_url_lines_are_preserved_when_visible_body_content
    html = "<body><p>before</p><p>https://example.com/standalone</p><p>after</p></body>"
    text = Goodmail::Plaintext.generate(html)

    assert_match(%r{^https://example\.com/standalone\s*$}, text)
    assert_includes text, "before"
    assert_includes text, "after"
  end

  def test_url_inside_a_sentence_is_preserved
    html = "<body><p>Visit https://example.com/foo for more details.</p></body>"
    text = Goodmail::Plaintext.generate(html)
    assert_includes text, "https://example.com/foo"
  end

  # ── info_row plaintext flattening ──────────────────────────────────

  def test_info_row_renders_as_a_single_label_colon_value_line_in_plaintext
    # A two-cell `<table class="goodmail-info-row">` extracts as
    # `Label\nValue` from Premailer by default — two lines for
    # what's logically a single property. Pre-processor flattens it
    # into the conventional `Label: Value` shape every other
    # transactional sender uses.
    body = build_dsl do
      info_row "Distancia", "18 km"
      info_row "Duración", "25 min"
    end
    text = Goodmail::Plaintext.generate(layout_html_with(text_body: body))
    assert_includes text, "Distancia: 18 km"
    assert_includes text, "Duración: 25 min"
    refute_match(/^Distancia\nDuración/, text, "label and value must NOT be on separate lines")
  end

  def test_multiple_info_rows_render_as_distinct_lines_not_one_run_on
    body = build_dsl do
      info_row "Distance", "18 km"
      info_row "Duration", "25 min"
      info_row "Driver", "Lola"
    end
    text = Goodmail::Plaintext.generate(layout_html_with(text_body: body))
    # Each Label: Value pair lives on its own line (with a blank
    # paragraph separator).
    assert_match(/Distance: 18 km/, text)
    assert_match(/Duration: 25 min/, text)
    assert_match(/Driver: Lola/, text)
    # And they're separate paragraphs, not concatenated.
    refute_match(/Distance: 18 km Duration:/, text)
  end

  def test_info_row_html_part_keeps_the_two_cell_table_for_pretty_visual_rendering
    # Check the OTHER side of the contract: in the HTML part the
    # two-cell table survives intact (the flatten is plaintext-only).
    body = build_dsl { info_row "Distancia", "18 km" }
    full_html = compose_full_layout(text_body: body)
    assert_match(/<table[^>]*goodmail-info-row[^>]*>/, full_html)
    assert_match(/<td[^>]*>Distancia<\/td>/, full_html)
    assert_match(/<td[^>]*>18 km<\/td>/, full_html)
  end

  def test_info_row_flatten_falls_back_to_unmodified_html_when_nokogiri_raises
    # The flatten step is wrapped in `rescue StandardError` so a
    # Nokogiri parse failure (truncated HTML, malformed input from a
    # custom layout) doesn't crash the whole email pipeline — we just
    # log to stderr and let Premailer extract the table cells as two
    # lines (ugly but not broken). Stub Nokogiri to raise and confirm
    # the email still ships and a warning lands on stderr.
    original = Nokogiri::HTML.method(:parse)
    Nokogiri::HTML.define_singleton_method(:parse) do |*args, **kwargs|
      raise "synthetic parser error"
    end

    body = build_dsl { info_row "Distancia", "18 km" }

    # Capture stderr so the test isn't noisy on a clean run AND we
    # can assert on the warning shape.
    original_stderr = $stderr
    $stderr = StringIO.new

    text = Goodmail::Plaintext.generate(layout_html_with(text_body: body))
    captured_warnings = $stderr.string

    # Output is degraded (cells on separate lines) but the pipeline
    # didn't crash — the recipient gets a slightly worse plaintext
    # rather than no email at all.
    assert_kind_of String, text
    assert_match(/info-row flatten failed.*synthetic parser error/, captured_warnings)
  ensure
    Nokogiri::HTML.define_singleton_method(:parse, original) if original
    $stderr = original_stderr if original_stderr
  end

  def test_info_row_plaintext_handles_special_characters_in_label_and_value
    body = build_dsl { info_row "Q&A: Plaza", "<b>2,50 €</b>" }
    text = Goodmail::Plaintext.generate(layout_html_with(text_body: body))
    # Both the label and the value get HTML-escaped at the Builder
    # level, then flattened. The Nokogiri pre-processor preserves the
    # escaped form when extracting `td.text`.
    assert_includes text, "Q&A: Plaza:"
    # Note: the value's `<b>` tags were escaped to `&lt;b&gt;` by
    # `info_row`, then Nokogiri's `td.text` decodes them back to
    # literal `<b>` characters in the plaintext output. That's the
    # same behavior as Premailer's text extractor, just earlier in
    # the pipeline.
    assert_includes text, "<b>2,50 €</b>"
  end

  # ── UTF-8 / accented character preservation ───────────────────────

  def test_accented_characters_survive_premailer_double_encoding
    # Regression guard: Premailer's libxml2 backend defaults to Latin-1
    # when the source HTML has no `<meta charset>` tag, double-encoding
    # every UTF-8 character (each byte in the multi-byte sequence gets
    # re-encoded as if it were a Latin-1 char). Goodmail pins
    # `input_encoding: "UTF-8"` on every Premailer call so even a
    # custom layout without the meta tag round-trips Spanish / French /
    # German accented characters cleanly.
    html = "<html><body><p>Duración: 25 min</p><p>Precio: 2,50 €</p></body></html>"
    text = Goodmail::Plaintext.generate(html)
    assert_includes text, "Duración"
    assert_includes text, "2,50 €"
    refute_includes text, "DuraciÃ³n", "looks like a UTF-8-double-encoded mojibake leak"
    refute_includes text, "â¬",        "looks like a Premailer Latin-1 fallback"
  end

  def test_accented_characters_survive_in_compose_path_too
    # Same UTF-8 round-trip from the public compose entry point so a
    # future regression in either the HTML or plaintext path surfaces.
    GoodmailTestConfig.configure(company_name: "Acme")
    Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "Subj"
    ) do
      text "Bienvenido a CarHey, donde compartimos viajes."
      info_row "Duración", "25 min"
      info_row "Distancia", "18 km"
      info_row "Precio", "2,50 €"
      sign
    end.deliver_now

    msg = ActionMailer::Base.deliveries.last
    text = msg.text_part.body.decoded
    [
      "Bienvenido", "Duración", "Distancia", "Precio", "2,50 €", "viajes"
    ].each do |needle|
      assert_includes text, needle, "plaintext should preserve UTF-8: #{needle.inspect}"
    end
    # And the same for the HTML part — Premailer is invoked there too,
    # with the same encoding gotcha.
    html = msg.html_part.body.decoded
    [ "Bienvenido", "Duración", "Distancia", "Precio", "2,50 €", "viajes" ].each do |needle|
      assert_includes html, needle, "HTML should preserve UTF-8: #{needle.inspect}"
    end
  end

  def test_accented_characters_in_emoji_and_high_BMP_codepoints
    # CJK + emoji round-trip as a stronger Unicode guarantee than
    # Latin-1-extension accents. If we ever silently downgrade to
    # Latin-1 these will manifest as `?` placeholders.
    html = "<html><body><p>こんにちは 🚗 résumé Übung</p></body></html>"
    text = Goodmail::Plaintext.generate(html)
    assert_includes text, "こんにちは"
    assert_includes text, "🚗"
    assert_includes text, "résumé"
    assert_includes text, "Übung"
  end

  # ── Regression: layout title text should not leak into plaintext ───

  def test_layout_title_tag_does_not_leak_into_plaintext
    # When the plaintext pre-processor uses Nokogiri on the source
    # HTML, it MUST parse as a full document — fragment parsing strips
    # the `<head>` wrapper and exposes the `<title>` text to
    # Premailer's plaintext extractor as a phantom first line.
    text = Goodmail::Plaintext.generate(compose_full_layout(text_body: "<p>visible body</p>"))
    refute_includes text, "Subject", "subject from <title> tag should not appear in plaintext"
    assert_includes text, "visible body"
  end

  # ── End-to-end via Goodmail.compose ────────────────────────────────

  def test_end_to_end_compose_plaintext_has_none_of_the_three_artifacts
    # The whole-pipeline check: a single Goodmail.compose call with the
    # exact shape that triggered all three bugs in production —
    # preheader, inline image, button. The plaintext should be clean.
    GoodmailTestConfig.configure(company_name: "Acme",
                                  logo_url: "https://cdn.example.com/logo.png",
                                  company_url: "https://example.com")
    Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "Subj",
      preheader: "Inbox preview text"
    ) do
      inline_image "hero.png", "FAKE_PNG_BYTES"
      text "Hello, this is the body."
      button "Open the receipt", "https://example.com/receipt"
      sign
    end.deliver_now

    msg = ActionMailer::Base.deliveries.last
    text = msg.text_part.body.decoded

    # 1. No preheader leak.
    refute_includes text, "Inbox preview text"
    # 2. No button text duplication.
    assert_equal 1, text.scan("Open the receipt").length,
                 "button label appeared more than once in plaintext"
    # 3. No company-name standalone alt leak.
    refute_match(/^Acme$/, text)
    # 4. The visible body content IS there.
    assert_includes text, "Hello, this is the body."
    # 5. The button's URL IS there (so plaintext is actually useful).
    assert_includes text, "https://example.com/receipt"
  end

  private

  # Wraps a body fragment in a minimal layout-shaped HTML document so
  # `Goodmail::Plaintext.generate` has the same kind of input it gets
  # in production. We don't use the actual layout.erb here because
  # most tests don't need the surrounding chrome.
  def layout_html_with(text_body:)
    <<~HTML
      <html>
        <body>
          <span style="display:none !important; font-size:1px; color:#ffffff;">Hidden preheader text</span>
          #{text_body}
        </body>
      </html>
    HTML
  end

  # Renders the FULL layout with the configured Goodmail surrounding
  # chrome — used when a test specifically asserts on layout-driven
  # plaintext artifacts (logo line, preheader span, copyright).
  def compose_full_layout(preheader: "Default preheader", text_body:)
    Goodmail::Layout.render(text_body, "Subject", preheader: preheader)
  end

  # Builds a snippet of DSL output for sticking inside a synthesized
  # layout. Uses `Builder#html_output` so the test sees exactly what
  # the production pipeline feeds to `Goodmail::Layout.render`.
  def build_dsl(&block)
    builder = Goodmail::Builder.new
    builder.instance_eval(&block)
    builder.html_output
  end
end
