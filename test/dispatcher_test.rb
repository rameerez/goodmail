# frozen_string_literal: true

require "test_helper"

# Tests for `Goodmail::Dispatcher` — the orchestration layer that wires
# Builder + Layout + Mailer together for the `Goodmail.compose(...)` path.
#
# We exercise the dispatcher directly here (`Goodmail::Dispatcher.build_message`)
# because `Goodmail.compose` is just a one-line delegate and the dispatcher
# is where the interesting branches live: header slicing, unsubscribe-URL
# fallback, preheader fallback chain, attachment plumbing.
class DispatcherTest < Minitest::Test
  def test_build_message_returns_an_ActionMailer_MessageDelivery
    delivery = Goodmail::Dispatcher.build_message(
      to: "user@example.com", from: "noreply@example.com", subject: "Subj"
    ) { text "hello" }
    assert_kind_of ActionMailer::MessageDelivery, delivery
  end

  def test_build_message_supports_calling_without_a_block
    # Edge case: caller may want a layout-only email (e.g. delivery-status
    # placeholder). The dispatcher must not crash on a missing block.
    delivery = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "Empty"
    )
    msg = delivery.message
    assert_kind_of Mail::Message, msg
    assert_equal ["u@x.co"], msg.to
  end

  def test_build_message_passes_to_from_subject_through_to_the_mail_object
    msg = Goodmail::Dispatcher.build_message(
      to: "alice@example.com", from: "bot@example.com", subject: "Hi Alice"
    ) { text "hello" }.message

    assert_equal ["alice@example.com"], msg.to
    assert_equal ["bot@example.com"], msg.from
    assert_equal "Hi Alice", msg.subject
  end

  def test_build_message_passes_cc_bcc_reply_to_through
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S",
      cc: "cc@x.co", bcc: "bcc@x.co", reply_to: "support@x.co"
    ) { text "hi" }.message

    assert_equal ["cc@x.co"], msg.cc
    assert_equal ["bcc@x.co"], msg.bcc
    assert_equal ["support@x.co"], msg.reply_to
  end

  def test_build_message_does_NOT_leak_unsubscribe_url_or_preheader_as_mail_headers
    # `:unsubscribe_url` and `:preheader` are Goodmail-specific options;
    # they must not be passed to ActionMailer's `mail()` method (which
    # treats unknown keys as headers and would emit them on the wire).
    # The dispatcher's `slice_mail_headers` filters them out — this test
    # locks that contract.
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S",
      unsubscribe_url: "https://example.com/u",
      preheader: "Inbox preview"
    ) { text "hi" }.message

    refute msg.header["unsubscribe_url"], "raw `unsubscribe_url` should not appear as a header"
    refute msg.header["preheader"], "raw `preheader` should not appear as a header"
    # But List-Unsubscribe (the actual standard header) IS set.
    assert_equal "<https://example.com/u>", msg["List-Unsubscribe"].value
  end

  def test_build_message_uses_explicit_unsubscribe_url_over_global_config
    GoodmailTestConfig.configure(unsubscribe_url: "https://example.com/global-u")
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S",
      unsubscribe_url: "https://example.com/explicit-u"
    ) { text "hi" }.message

    assert_equal "<https://example.com/explicit-u>", msg["List-Unsubscribe"].value
  end

  def test_build_message_falls_back_to_global_unsubscribe_url
    GoodmailTestConfig.configure(unsubscribe_url: "https://example.com/global-u")
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S"
    ) { text "hi" }.message

    assert_equal "<https://example.com/global-u>", msg["List-Unsubscribe"].value
  end

  def test_build_message_skips_unsubscribe_headers_when_no_url_anywhere
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S"
    ) { text "hi" }.message

    assert_nil msg["List-Unsubscribe"]
    assert_nil msg["List-Unsubscribe-Post"]
  end

  def test_build_message_uses_explicit_preheader_in_the_body
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S",
      preheader: "Custom preview"
    ) { text "hi" }.message

    html = msg.html_part.body.decoded
    assert_includes html, "Custom preview"
  end

  def test_build_message_falls_back_to_config_default_preheader
    GoodmailTestConfig.configure(default_preheader: "Default preview")
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "Subj"
    ) { text "hi" }.message

    assert_includes msg.html_part.body.decoded, "Default preview"
  end

  def test_build_message_falls_back_to_subject_when_no_preheader_anywhere
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "Last-Resort Preview"
    ) { text "hi" }.message

    # The subject lands in <title>, in <meta itemprop="name">, AND in the
    # hidden preheader span.
    assert_operator msg.html_part.body.decoded.scan("Last-Resort Preview").length, :>=, 2
  end

  def test_build_message_passes_DSL_attachments_through_to_the_mailer
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S"
    ) do
      text "see attached"
      attach "receipt.pdf", "PDF_BYTES", mime_type: "application/pdf"
    end.message

    pdf = msg.attachments.find { |a| a.filename == "receipt.pdf" }
    refute_nil pdf
    refute pdf.inline?
  end

  def test_build_message_handles_inline_image_attachments_and_pins_their_CIDs
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S"
    ) do
      inline_image "logo.png", "PNG_BYTES", alt: "Logo"
    end.message

    logo = msg.attachments.find { |a| a.filename == "logo.png" }
    refute_nil logo
    assert logo.inline?
    assert_equal "<logo.png>", logo.content_id
  end

  def test_build_message_calls_the_block_in_Builder_context
    # The block uses `instance_eval` on the Builder, so DSL methods like
    # `text` / `button` are reachable as bare identifiers. This test
    # confirms that side-effects (raising an error) propagate cleanly.
    error = assert_raises(RuntimeError) do
      Goodmail::Dispatcher.build_message(to: "u@x.co", from: "n@x.co", subject: "S") do
        text "before"
        raise "boom from inside the block"
      end
    end
    assert_match(/boom from inside the block/, error.message)
  end

  def test_build_message_renders_the_body_as_a_complete_HTML_document
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "Doc"
    ) { text "hello" }.message

    html = msg.html_part.body.decoded
    assert html.include?("<!DOCTYPE html>"), "body should be a full HTML document"
    assert_includes html, "<title>Doc</title>"
  end

  def test_build_message_emits_a_text_part_alongside_the_html_part
    msg = Goodmail::Dispatcher.build_message(
      to: "u@x.co", from: "n@x.co", subject: "S"
    ) { text "hello world" }.message

    refute_nil msg.text_part
    refute_nil msg.html_part
    assert_includes msg.text_part.body.decoded, "hello world"
  end

  # ── header slicing (the only private surface the dispatcher exposes
  # via `private` — we use `send` because covering the slicing in
  # isolation makes regressions immediately localizable). ─────────────

  def test_slice_mail_headers_keeps_only_the_standard_envelope_keys
    # Allowed: to, from, cc, bcc, reply_to, subject. Everything else
    # (Goodmail-specific: unsubscribe_url, preheader, layout_path; and
    # arbitrary unknown keys) should be filtered out — they'd otherwise
    # become Mail headers via ActionMailer's catch-all behavior.
    sliced = Goodmail::Dispatcher.send(:slice_mail_headers, {
      to: "a", from: "b", cc: "c", bcc: "d", reply_to: "e", subject: "S",
      unsubscribe_url: "u", preheader: "p", layout_path: "/dev/null", random: 1
    })
    assert_equal %i[to from cc bcc reply_to subject].sort, sliced.keys.sort
    refute sliced.key?(:unsubscribe_url)
    refute sliced.key?(:preheader)
    refute sliced.key?(:layout_path)
    refute sliced.key?(:random)
  end

  def test_slice_mail_headers_returns_an_empty_hash_when_nothing_matches
    sliced = Goodmail::Dispatcher.send(:slice_mail_headers, { unsubscribe_url: "u" })
    assert_equal({}, sliced)
  end
end
