# frozen_string_literal: true

require "test_helper"
require "tempfile"

# End-to-end tests for `Goodmail.compose` — the public, top-level API
# documented in the README. These tests verify the gem from the user's
# perspective: build a Mail::Message, deliver it, then introspect the
# encoded message exactly as a recipient's MTA would see it.
#
# Action Mailer's `:test` delivery method (set in test_helper) captures
# `deliver_now` calls into `ActionMailer::Base.deliveries` so we can
# assert on the on-the-wire message without sending real mail.
class ComposeTest < Minitest::Test
  def test_compose_returns_a_MessageDelivery_that_responds_to_deliver_now
    delivery = Goodmail.compose(to: "u@x.co", from: "n@x.co", subject: "Hi") { text "hi" }
    assert_kind_of ActionMailer::MessageDelivery, delivery
    assert_respond_to delivery, :deliver_now
    assert_respond_to delivery, :deliver_later
  end

  def test_compose_delivers_to_ActionMailer_test_inbox
    Goodmail.compose(
      to: "alice@example.com", from: "bot@example.com", subject: "Test"
    ) { text "hello" }.deliver_now

    assert_equal 1, ActionMailer::Base.deliveries.length
    msg = ActionMailer::Base.deliveries.last
    assert_equal ["alice@example.com"], msg.to
    assert_equal ["bot@example.com"], msg.from
    assert_equal "Test", msg.subject
  end

  def test_compose_renders_a_full_multipart_message_with_html_and_text_parts
    Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "Multipart"
    ) { text "hello world" }.deliver_now

    msg = ActionMailer::Base.deliveries.last
    assert_match(%r{multipart/alternative}, msg.content_type)
    refute_nil msg.html_part
    refute_nil msg.text_part
    assert_includes msg.html_part.body.decoded, "<!DOCTYPE html>"
    assert_includes msg.text_part.body.decoded, "hello world"
  end

  def test_compose_passes_ActionMailer_headers_through_after_stripping_Goodmail_options
    sent_at = Time.utc(2026, 5, 21, 12, 30, 0)
    msg = Goodmail.compose(
      to: "u@x.co",
      from: "n@x.co",
      subject: "Headers",
      date: sent_at,
      "X-Correlation-ID" => "abc-123",
      preheader: "Preview",
      unsubscribe_url: "https://example.com/u"
    ) { text "hello" }.message

    assert_equal sent_at.to_datetime, msg.date
    assert_equal "abc-123", msg["X-Correlation-ID"].value
    assert_nil msg["preheader"]
    assert_nil msg["unsubscribe_url"]
  end

  def test_compose_uses_custom_layout_path_without_leaking_it_as_a_mail_header
    Tempfile.create(["goodmail-compose-layout", ".erb"]) do |file|
      file.write("<html><body>CUSTOM-LAYOUT <%= body_html %></body></html>")
      file.flush

      msg = Goodmail.compose(
        to: "u@x.co", from: "n@x.co", subject: "Custom layout",
        layout_path: file.path
      ) { text "custom body" }.message

      assert_includes msg.html_part.body.decoded, "CUSTOM-LAYOUT"
      assert_includes msg.html_part.body.decoded, "custom body"
      assert_nil msg["layout_path"]
    end
  end

  def test_compose_can_be_called_with_only_required_headers_no_block
    # Edge case from the dispatcher: no block. The compose path should
    # still produce a deliverable Mail::Message.
    delivery = Goodmail.compose(to: "u@x.co", from: "n@x.co", subject: "Empty")
    delivery.deliver_now
    assert_equal 1, ActionMailer::Base.deliveries.length
  end

  def test_compose_emits_RFC_8058_one_click_unsubscribe_header_pair
    # End-to-end check that the gem's headline deliverability fix is in
    # the encoded message a real MTA would forward. RFC 8058 requires
    # the one-click URL to be HTTPS.
    msg = Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "Unsub",
      unsubscribe_url: "https://example.com/u/42"
    ) { text "hi" }.message

    encoded = msg.encoded
    assert_includes encoded, "List-Unsubscribe: <https://example.com/u/42>"
    assert_includes encoded, "List-Unsubscribe-Post: List-Unsubscribe=One-Click"
  end

  def test_compose_does_not_emit_one_click_post_for_http_unsubscribe_url
    msg = Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "Unsub",
      unsubscribe_url: "http://example.com/u/42"
    ) { text "hi" }.message

    assert_equal "<http://example.com/u/42>", msg["List-Unsubscribe"].value
    assert_nil msg["List-Unsubscribe-Post"]
  end

  def test_compose_inline_image_round_trips_through_a_real_delivery
    Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "Hero"
    ) do
      inline_image "hero.png", "FAKE\x89PNG_BYTES_WITH_\x00_NUL".b
      text "see the hero above"
    end.deliver_now

    msg = ActionMailer::Base.deliveries.last
    hero = msg.attachments.find { |a| a.filename == "hero.png" }
    refute_nil hero
    assert hero.inline?
    assert_match(/\A<[0-9a-f]{24}\.hero\.png@inline\.goodmail\.invalid>\z/, hero.content_id)

    # The body's generated `cid:` reference resolves to the part above.
    content_id = hero.content_id.delete_prefix("<").delete_suffix(">")
    assert_match(/<img[^>]+src="cid:#{Regexp.escape(content_id)}"/, msg.html_part.body.decoded)
  end

  def test_compose_uses_global_config_brand_color_in_the_button
    GoodmailTestConfig.configure(brand_color: "#abcdef")
    msg = Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "S"
    ) { button "Click me", "https://example.com" }.message

    html = msg.html_part.body.decoded
    # Premailer inlines the brand color onto the anchor's `background-color`.
    assert_includes html, "#abcdef"
  end

  def test_compose_uses_global_config_company_name_in_the_signature
    GoodmailTestConfig.configure(company_name: "Acme Inc.")
    msg = Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "S"
    ) { sign }.message

    assert_includes msg.html_part.body.decoded, "Acme Inc."
  end

  def test_compose_accepts_a_per_message_config_override
    GoodmailTestConfig.configure(company_name: "Global Co.", brand_color: "#111827")

    msg = Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "S",
      config: { company_name: "Tenant Co.", brand_color: "#ff5500", unsubscribe_url: "https://tenant.example/u" }
    ) do
      button "Click me", "https://example.com"
      sign
    end.message

    assert_includes msg.html_part.body.decoded, "Tenant Co."
    assert_includes msg.html_part.body.decoded, "#ff5500"
    assert_equal "<https://tenant.example/u>", msg["List-Unsubscribe"].value
    assert_nil msg["config"]
    assert_equal "Global Co.", Goodmail.config.company_name
  end

  def test_compose_snapshots_effective_config_for_lazy_message_materialization
    GoodmailTestConfig.configure(company_name: "OriginalCo", brand_color: "#111827")
    delivery = Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "Lazy config"
    ) do
      image "https://cdn.example.com/banner.png"
      text "Body after image"
    end

    refute delivery.processed?

    GoodmailTestConfig.configure(company_name: "ChangedCo", brand_color: "#000000")
    msg = delivery.message

    assert_includes msg.html_part.body.decoded, "OriginalCo"
    refute_includes msg.html_part.body.decoded, "ChangedCo"
    assert_includes msg.text_part.body.decoded, "Body after image"
    refute_match(/^OriginalCo$/, msg.text_part.body.decoded)
  end

  def test_compose_full_kitchen_sink_block_round_trips
    # One block exercising every visible DSL helper plus attachments.
    # If any helper later regresses (errors, garbled output, missing
    # styles), this test surfaces it without requiring the contributor
    # to read the per-helper unit tests.
    delivery = Goodmail.compose(
      to: "kitchen@example.com", from: "sink@example.com",
      subject: "Kitchen sink",
      unsubscribe_url: "https://example.com/u",
      preheader: "Kitchen sink preview",
      cc: "cc@example.com",
      reply_to: "support@example.com"
    ) do
      h1 "Big Title"
      h2 "Mid title"
      h3 "Small title"
      text "<strong>Important:</strong> this email exercises every DSL surface."
      space 24
      info_row "Distance", "18 km"
      info_row "Duration", "25 min"
      price_row "Premium plan", "$49.00"
      code_box "ABC-123"
      center { text "centered text" }
      line
      link "Read the policy", "https://example.com/policy"
      small "Fine print and disclaimers."
      button "Open the receipt", "https://example.com/r/1"
      image "https://cdn.example.com/banner.png", "Banner", width: 600
      attach "receipt.pdf", "PDF_BYTES", mime_type: "application/pdf"
      inline_image "logo.png", "PNG_BYTES", alt: "Logo"
      sign
    end

    delivery.deliver_now
    msg = ActionMailer::Base.deliveries.last

    # Headers
    assert_equal ["kitchen@example.com"], msg.to
    assert_equal ["cc@example.com"], msg.cc
    assert_equal ["support@example.com"], msg.reply_to
    assert_equal "Kitchen sink", msg.subject
    assert_equal "<https://example.com/u>", msg["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", msg["List-Unsubscribe-Post"].value

    # Attachments
    filenames = msg.attachments.map(&:filename).sort
    assert_equal ["logo.png", "receipt.pdf"], filenames
    assert msg.attachments.find { |a| a.filename == "logo.png" }.inline?
    refute msg.attachments.find { |a| a.filename == "receipt.pdf" }.inline?

    # Body content
    html = msg.html_part.body.decoded
    [
      "Big Title", "Mid title", "Small title",
      "<strong>Important:</strong>",
      "Distance", "18 km", "Duration", "25 min",
      "Premium plan", "$49.00",
      "ABC-123",
      "centered text",
      "Read the policy", "https://example.com/policy",
      "Fine print and disclaimers.",
      "Open the receipt", "https://example.com/r/1",
      "https://cdn.example.com/banner.png",
      "inline.goodmail.invalid",
      "Test Co.", # signature
      "Kitchen sink preview" # preheader
    ].each do |needle|
      assert_includes html, needle, "kitchen-sink HTML missing: #{needle.inspect}"
    end

    # Plain-text body (Premailer-derived)
    text = msg.text_part.body.decoded
    assert_includes text, "Big Title"
    assert_includes text, "this email exercises every DSL surface"
    assert_includes text, "Open the receipt"
  end

  def test_compose_does_NOT_mutate_the_caller_provided_headers_hash
    headers = { to: "u@x.co", from: "n@x.co", subject: "S",
                unsubscribe_url: "https://example.com/u",
                preheader: "Hello" }
    snapshot = headers.dup
    Goodmail.compose(headers) { text "hi" }.message
    assert_equal snapshot, headers, "compose must not mutate the caller's headers hash"
  end
end
