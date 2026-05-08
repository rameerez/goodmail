# frozen_string_literal: true

require "test_helper"

# Tests for `Goodmail::EmailParts` (the data struct) and `Goodmail.render`
# (the entry point that composes Builder + Layout + Premailer and returns
# the parts struct, ready for a custom mailer to call `mail()` itself).
#
# `Goodmail.render` is the recommended path for apps that want to integrate
# with Devise / Pay / org-invite mailers without giving up control over
# the mail object — `Goodmail.compose` is for one-shot use cases.
class EmailTest < Minitest::Test
  # ── EmailParts struct ───────────────────────────────────────────────

  def test_EmailParts_accepts_keyword_init
    parts = Goodmail::EmailParts.new(html: "<p>h</p>", text: "t", attachments: [{ filename: "x" }])
    assert_equal "<p>h</p>", parts.html
    assert_equal "t", parts.text
    assert_equal [{ filename: "x" }], parts.attachments
  end

  def test_EmailParts_attachments_defaults_to_empty_array_when_omitted
    # Backwards-compat hook: 0.3.x callers that pre-date the attachments
    # field still get a workable struct without having to know about it.
    parts = Goodmail::EmailParts.new(html: "<p>h</p>", text: "t")
    assert_equal [], parts.attachments
  end

  def test_EmailParts_coerces_explicit_nil_attachments_to_empty_array
    parts = Goodmail::EmailParts.new(html: "<p>h</p>", text: "t", attachments: nil)
    assert_equal [], parts.attachments
  end

  def test_EmailParts_html_and_text_default_to_nil
    parts = Goodmail::EmailParts.new
    assert_nil parts.html
    assert_nil parts.text
    assert_equal [], parts.attachments
  end

  # ── Goodmail.render — happy path ────────────────────────────────────

  def test_render_returns_an_EmailParts_instance
    parts = Goodmail.render(subject: "Subj") { text "hello" }
    assert_kind_of Goodmail::EmailParts, parts
    assert_kind_of String, parts.html
    assert_kind_of String, parts.text
    assert_kind_of Array,  parts.attachments
  end

  def test_render_inlines_styles_via_premailer
    parts = Goodmail.render(subject: "Subj") { text "hello" }
    # Premailer pushes the layout's <style> rules onto the inline-style
    # attribute of every visible element; the <style> block itself goes
    # away under `preserve_styles: false`.
    refute_match(/<style[^>]*type="text\/css"/, parts.html, "premailer should have inlined and removed the <style> block")
    assert_match(/<p style="[^"]*line-height: 1\.6;[^"]*">hello<\/p>/, parts.html)
  end

  def test_render_generates_a_plain_text_part_alongside_the_html
    parts = Goodmail.render(subject: "Subj") do
      text "Hello, world!"
      button "Open it", "https://example.com"
    end
    assert_includes parts.text, "Hello, world!"
    assert_includes parts.text, "Open it"
    refute_includes parts.text, "<p>"
    refute_includes parts.text, "<a "
  end

  # ── Goodmail.render — block execution semantics ─────────────────────

  def test_render_with_no_block_still_returns_a_well_formed_struct
    parts = Goodmail.render(subject: "Subj")
    assert_kind_of Goodmail::EmailParts, parts
    assert_kind_of String, parts.html
    assert_kind_of String, parts.text
    assert_equal [], parts.attachments
  end

  def test_render_propagates_attachments_collected_by_the_DSL_block
    parts = Goodmail.render(subject: "Subj") do
      attach "receipt.pdf", "PDF_BYTES", mime_type: "application/pdf"
      inline_image "logo.png", "PNG_BYTES", alt: "Logo"
    end
    assert_equal 2, parts.attachments.length
    pdf = parts.attachments.find { |a| a[:filename] == "receipt.pdf" }
    png = parts.attachments.find { |a| a[:filename] == "logo.png" }
    refute_nil pdf
    refute_nil png
    assert_equal "application/pdf", pdf[:mime_type]
    assert_equal false, pdf[:inline]
    assert_equal true, png[:inline]
  end

  # ── Goodmail.render — header handling ───────────────────────────────

  def test_render_does_not_mutate_the_caller_provided_headers_hash
    headers = { subject: "Subj", unsubscribe_url: "https://x.co/u", preheader: "Hi" }
    snapshot = headers.dup
    Goodmail.render(headers) { text "hello" }
    assert_equal snapshot, headers, "render must not mutate the caller's headers hash in-place"
  end

  def test_render_uses_explicit_unsubscribe_url_in_the_layout_footer
    GoodmailTestConfig.configure(show_footer_unsubscribe_link: true)
    parts = Goodmail.render(subject: "Subj", unsubscribe_url: "https://example.com/u/42") do
      text "hello"
    end
    assert_includes parts.html, 'href="https://example.com/u/42"'
  end

  def test_render_falls_back_to_global_unsubscribe_url_when_header_omitted
    GoodmailTestConfig.configure(show_footer_unsubscribe_link: true, unsubscribe_url: "https://example.com/global")
    parts = Goodmail.render(subject: "Subj") { text "hello" }
    assert_includes parts.html, 'href="https://example.com/global"'
  end

  def test_render_uses_explicit_preheader_when_passed
    parts = Goodmail.render(subject: "Subj", preheader: "Custom preview") { text "hello" }
    assert_includes parts.html, "Custom preview"
  end

  def test_render_falls_back_to_config_default_preheader_when_omitted
    GoodmailTestConfig.configure(default_preheader: "Default preview")
    parts = Goodmail.render(subject: "Subj") { text "hello" }
    assert_includes parts.html, "Default preview"
  end

  def test_render_falls_back_to_subject_for_preheader_when_neither_set
    parts = Goodmail.render(subject: "Last-Resort Subject") { text "hello" }
    # Subject appears in <title>, in the meta itemprop, AND in the
    # hidden preheader span — at least 2 occurrences.
    assert_operator parts.html.scan("Last-Resort Subject").length, :>=, 2
  end

  # ── Goodmail.render — plaintext cleanup ────────────────────────────

  def test_render_strips_logo_alt_text_line_when_logo_and_company_url_configured
    GoodmailTestConfig.configure(
      logo_url: "https://cdn.example.com/logo.png",
      company_url: "https://example.com",
      company_name: "Acme"
    )
    parts = Goodmail.render(subject: "Subj") { text "Body content here." }
    refute_match(/Acme\s+Logo\s*\(.*example\.com.*\)/, parts.text)
  end

  def test_render_strips_standalone_url_lines_from_plaintext
    # The cleanup regex targets lines that consist *only* of a URL —
    # those almost always come from logo links or similar artifacts that
    # Premailer renders as a footnote-style URL on its own line. The
    # regex is anchored to start/end of line so URLs inline with text
    # (like a sentence "visit https://x.co for more") survive.
    parts = Goodmail.render(subject: "Subj") do
      image "https://cdn.example.com/standalone.png", "alt"
      text "Some body text that mentions https://example.com inline."
    end
    refute_match(/^https?:\/\/cdn\.example\.com\/standalone\.png\s*$/, parts.text)
    assert_includes parts.text, "https://example.com inline"
  end

  def test_render_compacts_excess_blank_lines_in_plaintext
    parts = Goodmail.render(subject: "Subj") do
      text "first"
      space 32
      space 32
      space 32
      text "second"
    end
    refute_match(/\n{3,}/, parts.text, "plaintext should never have 3+ consecutive newlines")
  end

  def test_render_strip_trailing_whitespace_on_plaintext
    parts = Goodmail.render(subject: "Subj") { text "hi" }
    refute_match(/\s\z/, parts.text)
    refute_match(/\A\s/, parts.text)
  end
end
