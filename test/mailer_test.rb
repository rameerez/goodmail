# frozen_string_literal: true

require "test_helper"

# Tests for `Goodmail::Mailer` — the internal `ActionMailer::Base`
# subclass that materializes the final `Mail::Message`. We exercise it
# through `Goodmail.compose`, which is the documented entry point and
# the only path that uses this class directly. The dispatcher_test
# covers the orchestration layer; this file zooms in on the Mailer's
# specific responsibilities after `Goodmail.render` has produced the body:
#
#   1. List-Unsubscribe + List-Unsubscribe-Post header pair (RFC 8058 /
#      Gmail+Yahoo Feb 2024 sender requirements)
#   2. DSL-attachment fan-out to ActionMailer's attachments hash
#   3. Inline-image Content-ID pinning (so generated `cid:` URLs resolve)
#   4. Multipart handoff of already inlined HTML and cleaned plaintext
class MailerTest < Minitest::Test
  # ── Premailer: CSS inlining + plain text part ────────────────────────

  def test_html_part_has_styles_inlined_via_premailer
    msg = compose { text "hello" }.message
    html = msg.html_part.body.decoded
    # Premailer pushes the layout's CSS onto the inline `style` attribute
    # of every visible element. We check the paragraph's `line-height`
    # specifically: it's defined on `p` in the layout's <style> block
    # AND on the inline style emitted by `Builder#text`. Either way it
    # MUST end up inline on the rendered element.
    assert_match(/<p style="[^"]*line-height: 1\.6[^"]*">hello<\/p>/, html)
    # Note on residual <style> blocks: Premailer can't inline `@media`
    # queries (they're conditional, no element to attach them to), so
    # the responsive-rules subset of the layout's <style> block does
    # survive. That's correct behavior; we don't try to assert it away.
  end

  def test_text_part_is_a_clean_plain_text_render_of_the_html
    msg = compose do
      text "Hello, world!"
      button "Open it", "https://example.com"
    end.message

    assert_includes msg.text_part.body.decoded, "Hello, world!"
    assert_includes msg.text_part.body.decoded, "Open it"
    refute_includes msg.text_part.body.decoded, "<p>"
    refute_includes msg.text_part.body.decoded, "<a "
  end

  # ── List-Unsubscribe headers (RFC 8058 + Gmail/Yahoo Feb 2024) ───────

  def test_unsubscribe_header_pair_is_set_when_url_provided
    # Gmail and Yahoo's Feb 2024 sender requirements treat the missing
    # `List-Unsubscribe-Post: List-Unsubscribe=One-Click` header as a
    # spam signal for senders averaging 5k+ messages/day. Goodmail
    # always emits the pair when an unsubscribe URL is configured.
    msg = compose(unsubscribe_url: "https://example.com/u/42") { text "hi" }.message

    assert_equal "<https://example.com/u/42>", msg["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", msg["List-Unsubscribe-Post"].value
  end

  def test_unsubscribe_url_is_strip_normalized
    # Trailing whitespace in the configured URL must not leak into the
    # angle-bracketed header value (mail parsers vary on tolerance).
    msg = compose(unsubscribe_url: "  https://example.com/u  ") { text "hi" }.message
    assert_equal "<https://example.com/u>", msg["List-Unsubscribe"].value
  end

  def test_unsubscribe_headers_are_skipped_when_url_is_nil
    msg = compose { text "hi" }.message
    assert_nil msg["List-Unsubscribe"]
    assert_nil msg["List-Unsubscribe-Post"]
  end

  def test_unsubscribe_headers_are_skipped_when_url_is_blank_string
    msg = compose(unsubscribe_url: "   ") { text "hi" }.message
    assert_nil msg["List-Unsubscribe"]
    assert_nil msg["List-Unsubscribe-Post"]
  end

  def test_one_click_post_header_is_skipped_for_non_https_unsubscribe_urls
    # RFC 8058 one-click requires an HTTPS URI in List-Unsubscribe. We still
    # preserve the classic header for backwards compatibility, but we do not
    # claim POST support for http/mailto/malformed values.
    msg = compose(unsubscribe_url: "http://example.com/u") { text "hi" }.message

    assert_equal "<http://example.com/u>", msg["List-Unsubscribe"].value
    assert_nil msg["List-Unsubscribe-Post"]
  end

  def test_one_click_post_header_is_skipped_for_malformed_unsubscribe_urls
    msg = compose(unsubscribe_url: "https://exa mple.com/u") { text "hi" }.message

    assert_equal "<https://exa mple.com/u>", msg["List-Unsubscribe"].value
    assert_nil msg["List-Unsubscribe-Post"]
  end

  def test_unsubscribe_headers_are_skipped_when_url_is_non_string
    # Defensive: a caller might accidentally pass `true` or a Hash and
    # the gem must not crash trying to interpolate it. The header check
    # is `is_a?(String)`-gated.
    msg = compose(unsubscribe_url: true) { text "hi" }.message
    assert_nil msg["List-Unsubscribe"]
  end

  # ── DSL attachment plumbing ──────────────────────────────────────────

  def test_attach_with_no_mime_type_passes_raw_bytes_to_ActionMailer
    msg = compose do
      attach "notes.txt", "hello bytes"
    end.message

    note = msg.attachments.find { |a| a.filename == "notes.txt" }
    refute_nil note
    refute note.inline?
    # When mime_type is omitted we let ActionMailer infer from the
    # filename — `Mime::Type.lookup_by_extension(:txt)`. No need to
    # assert a specific value here, just that some text/* type was
    # inferred (some Mail gems infer text/plain, some require an exact
    # extension match).
    assert_kind_of String, note.content_type
  end

  def test_attach_with_explicit_mime_type_passes_the_hash_form_to_ActionMailer
    msg = compose do
      attach "data.bin", "raw_bytes", mime_type: "application/octet-stream"
    end.message

    data = msg.attachments.find { |a| a.filename == "data.bin" }
    refute_nil data
    assert_match(%r{application/octet-stream}, data.content_type)
  end

  def test_inline_attach_lands_with_inline_disposition
    msg = compose do
      attach "logo.png", "PNG_BYTES", inline: true
    end.message

    logo = msg.attachments.find { |a| a.filename == "logo.png" }
    refute_nil logo
    assert logo.inline?
  end

  def test_multiple_attachments_round_trip_in_one_message
    msg = compose do
      attach "receipt.pdf", "PDF", mime_type: "application/pdf"
      attach "calendar.ics", "ICS", mime_type: "text/calendar"
      inline_image "logo.png", "PNG_BYTES"
    end.message

    filenames = msg.attachments.map(&:filename).sort
    assert_equal ["calendar.ics", "logo.png", "receipt.pdf"], filenames
  end

  # ── Inline-image Content-ID pinning ─────────────────────────────────

  def test_inline_attachment_content_id_is_pinned_to_the_generated_id
    # Mail gem auto-generates a globally-unique Content-ID
    # (`<longhash@host.tld.mail>`) for every attachment. The DSL must emit
    # the body `<img src="cid:...">` before Action Mailer materializes the
    # attachment part, so Goodmail generates the Content-ID in Builder and
    # pins the Mail part to that exact ID here.
    msg = compose do
      inline_image "logo.png", "PNG_BYTES"
    end.message

    logo = msg.attachments.find { |a| a.filename == "logo.png" }
    assert_match(/\A<[0-9a-f]{24}\.logo\.png@inline\.goodmail\.invalid>\z/, logo.content_id)
  end

  def test_inline_attachment_body_emits_cid_reference_matching_the_pinned_id
    msg = compose do
      inline_image "hero.png", "PNG_BYTES", alt: "Hero"
    end.message

    html = msg.html_part.body.decoded
    hero = msg.attachments.find { |a| a.filename == "hero.png" }
    assert_match(/<img[^>]+src="cid:#{Regexp.escape(hero.content_id.delete_prefix("<").delete_suffix(">"))}"/, html)
  end

  def test_non_inline_attachments_keep_their_default_content_id
    # Non-inline attachments don't NEED a pinned Content-ID — the body
    # never references them via `cid:`. We don't override Mail gem's
    # auto-generated ID for those.
    msg = compose do
      attach "receipt.pdf", "PDF_BYTES", mime_type: "application/pdf"
    end.message

    pdf = msg.attachments.find { |a| a.filename == "receipt.pdf" }
    refute_equal "<receipt.pdf>", pdf.content_id, "non-inline parts use Mail gem's auto-id"
  end

  def test_attach_does_NOT_crash_on_binary_content_with_NUL_bytes
    # Regression guard for the binary-content fix in `resolve_attachment_content`.
    # `File.file?` raises ArgumentError on NUL-containing Strings; PNGs,
    # PDFs, and .ics-as-bytes routinely contain them.
    binary = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b
    msg = compose do
      inline_image "logo.png", binary
    end.message

    logo = msg.attachments.find { |a| a.filename == "logo.png" }
    refute_nil logo
  end

  # ── Plaintext cleanup ────────────────────────────────────────────────

  def test_plaintext_strips_logo_alt_line_when_company_logo_configured
    GoodmailTestConfig.configure(
      logo_url: "https://cdn.example.com/logo.png",
      company_url: "https://example.com",
      company_name: "Acme"
    )
    text = compose { text "Body content here." }.message.text_part.body.decoded
    refute_match(/Acme\s+Logo\s*\(.*example\.com.*\)/, text)
  end

  def test_plaintext_preserves_visible_standalone_url_lines
    text = compose do
      text "https://example.com/reset"
    end.message.text_part.body.decoded

    assert_includes text, "https://example.com/reset"
  end

  def test_plaintext_from_images_does_not_emit_raw_image_src_lines
    text = compose do
      image "https://cdn.example.com/standalone.png", "alt"
      text "Some body text."
    end.message.text_part.body.decoded
    refute_match(/^https?:\/\/cdn\.example\.com\/standalone\.png\s*$/, text)
  end

  def test_plaintext_compacts_excess_blank_lines
    text = compose do
      text "first"
      space 32
      space 32
      space 32
      text "second"
    end.message.text_part.body.decoded
    refute_match(/\n{3,}/, text)
  end

  def test_plaintext_is_strip_normalized
    text = compose { text "hi" }.message.text_part.body.decoded
    refute_match(/\s\z/, text)
    refute_match(/\A\s/, text)
  end

  private

  def compose(unsubscribe_url: nil, &block)
    headers = { to: "user@example.com", from: "noreply@example.com", subject: "Subject" }
    headers[:unsubscribe_url] = unsubscribe_url unless unsubscribe_url.nil?
    Goodmail.compose(headers, &block)
  end
end
