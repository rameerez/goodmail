# frozen_string_literal: true

require "test_helper"

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

  def test_compose_can_be_called_with_only_required_headers_no_block
    # Edge case from the dispatcher: no block. The compose path should
    # still produce a deliverable Mail::Message.
    delivery = Goodmail.compose(to: "u@x.co", from: "n@x.co", subject: "Empty")
    delivery.deliver_now
    assert_equal 1, ActionMailer::Base.deliveries.length
  end

  def test_compose_emits_RFC_8058_one_click_unsubscribe_header_pair
    # End-to-end check that the gem's headline deliverability fix is in
    # the encoded message a real MTA would forward.
    msg = Goodmail.compose(
      to: "u@x.co", from: "n@x.co", subject: "Unsub",
      unsubscribe_url: "https://example.com/u/42"
    ) { text "hi" }.message

    encoded = msg.encoded
    assert_includes encoded, "List-Unsubscribe: <https://example.com/u/42>"
    assert_includes encoded, "List-Unsubscribe-Post: List-Unsubscribe=One-Click"
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
    assert_equal "<hero.png>", hero.content_id

    # The body's `<img src="cid:hero.png">` reference resolves to the
    # part above — the round-trip property the 0.4.2 fix locked in.
    assert_match(/<img[^>]+src="cid:hero\.png"/, msg.html_part.body.decoded)
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
      "cid:logo.png",
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
