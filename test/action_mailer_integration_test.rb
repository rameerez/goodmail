# frozen_string_literal: true

require "test_helper"
require "tempfile"

class GoodmailIntegrationMailer < ActionMailer::Base
  default from: "sender@example.com"

  def wrapped(headers = {})
    goodmail_mail(headers) do
      text "Wrapped body"
    end
  end

  def wrapped_inline(headers = {})
    goodmail_mail(headers) do
      inline_image "logo.png", "PNG_BYTES", alt: "Logo", mime_type: "image/png"
      text "Logo body"
    end
  end

  def pre_rendered(headers = {}, render_options = {})
    parts = goodmail_render_parts(render_options) do
      inline_image "hero.png", "PNG_BYTES", alt: "Hero", mime_type: "image/png"
      text "Pre-rendered body"
    end

    goodmail_mail_parts(parts, headers, unsubscribe_url: render_options[:unsubscribe_url])
  end

  def pre_rendered_with_header_unsubscribe(headers = {})
    parts = goodmail_render_parts(subject: headers[:subject]) do
      text "Header unsubscribe body"
    end

    goodmail_mail_parts(parts, headers)
  end

  def pre_rendered_context(headers = {})
    @recipient_name = "Avery"

    parts = goodmail_render_parts(subject: headers[:subject]) do
      text "Hello #{@recipient_name}"
      link "Open dashboard", dashboard_url(account_id: 42)
    end

    goodmail_mail_parts(parts, headers, unsubscribe_url: nil)
  end

  def legacy_parts(headers = {})
    legacy = Struct.new(:html, :text).new("<p>Legacy body</p>", "Legacy body")
    goodmail_mail_parts(legacy, headers, unsubscribe_url: nil)
  end

  def context_wrapped(headers = {})
    @recipient_name = "Avery"

    goodmail_mail(headers) do
      text "Hello #{@recipient_name}"
      link "Open dashboard", dashboard_url(account_id: 42)
    end
  end

  def wrapped_with_config(headers = {})
    goodmail_mail(headers) do
      button "Open", "https://example.test/open"
      sign
    end
  end

  private

  def dashboard_url(account_id:)
    "https://example.test/accounts/#{account_id}"
  end
end

class ActionMailerIntegrationTest < Minitest::Test
  def test_list_unsubscribe_headers_returns_classic_and_one_click_headers_for_https
    headers = Goodmail.list_unsubscribe_headers(" https://example.com/u ")

    assert_equal "<https://example.com/u>", headers["List-Unsubscribe"]
    assert_equal "List-Unsubscribe=One-Click", headers["List-Unsubscribe-Post"]
  end

  def test_list_unsubscribe_headers_keeps_classic_header_only_for_non_https
    headers = Goodmail.list_unsubscribe_headers("http://example.com/u")

    assert_equal "<http://example.com/u>", headers["List-Unsubscribe"]
    assert_nil headers["List-Unsubscribe-Post"]
  end

  def test_list_unsubscribe_headers_returns_empty_hash_for_blank_or_non_string_values
    assert_empty Goodmail.list_unsubscribe_headers(nil)
    assert_empty Goodmail.list_unsubscribe_headers("")
    assert_empty Goodmail.list_unsubscribe_headers(true)
  end

  def test_one_click_unsubscribe_url_rejects_invalid_urls
    refute Goodmail.one_click_unsubscribe_url?("https://example .com/unsubscribe")
  end

  def test_integration_methods_are_not_action_mailer_actions
    actions = GoodmailIntegrationMailer.action_methods

    assert_includes ActionMailer::Base.private_instance_methods, :goodmail_mail
    assert_includes GoodmailIntegrationMailer.private_instance_methods, :goodmail_mail_parts
    refute_includes actions, "goodmail_mail"
    refute_includes actions, "goodmail_render_parts"
    refute_includes actions, "goodmail_mail_parts"
    refute_includes actions, "goodmail_apply_parts!"
  end

  def test_action_mailer_integration_install_is_idempotent
    before = ActionMailer::Base.ancestors.count(Goodmail::ActionMailerIntegration)

    Goodmail.install_action_mailer_integration!

    assert_equal before, ActionMailer::Base.ancestors.count(Goodmail::ActionMailerIntegration)
  end

  def test_instance_header_helper_delegates_to_goodmail_headers
    headers = GoodmailIntegrationMailer.new.send(
      :goodmail_list_unsubscribe_headers,
      "https://example.com/u"
    )

    assert_equal "<https://example.com/u>", headers["List-Unsubscribe"]
    assert_equal "List-Unsubscribe=One-Click", headers["List-Unsubscribe-Post"]
  end

  def test_goodmail_mail_renders_and_sends_multipart_message
    msg = GoodmailIntegrationMailer.wrapped(
      to: "user@example.com",
      subject: "Wrapped",
      preheader: "Preview text",
      unsubscribe_url: "https://example.com/u"
    ).message

    assert_equal ["user@example.com"], msg.to
    assert_equal "Wrapped", msg.subject
    assert_includes msg.text_part.body.decoded, "Wrapped body"
    assert_includes msg.html_part.body.decoded, "Wrapped body"
    assert_nil msg["preheader"]
    assert_nil msg["unsubscribe_url"]
    assert_equal "<https://example.com/u>", msg["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", msg["List-Unsubscribe-Post"].value
  end

  def test_goodmail_mail_evaluates_blocks_with_the_mailer_context
    msg = GoodmailIntegrationMailer.context_wrapped(
      to: "user@example.com",
      subject: "Context"
    ).message

    assert_includes msg.text_part.body.decoded, "Hello Avery"
    assert_includes msg.html_part.body.decoded, "Hello Avery"
    assert_includes msg.html_part.body.decoded, "https://example.test/accounts/42"
    assert_nil msg["context"]
  end

  def test_goodmail_mail_supports_per_message_config_overrides
    GoodmailTestConfig.configure(company_name: "Global Co.", brand_color: "#111827")

    msg = GoodmailIntegrationMailer.wrapped_with_config(
      to: "user@example.com",
      subject: "Whitelabel",
      config: { company_name: "Tenant Co.", brand_color: "#ff5500", unsubscribe_url: "https://tenant.example/u" }
    ).message

    assert_includes msg.html_part.body.decoded, "Tenant Co."
    assert_includes msg.html_part.body.decoded, "#ff5500"
    assert_equal "<https://tenant.example/u>", msg["List-Unsubscribe"].value
    assert_nil msg["config"]
    assert_equal "Global Co.", Goodmail.config.company_name
  end

  def test_goodmail_mail_passes_custom_ActionMailer_headers_through
    sent_at = Time.utc(2026, 5, 21, 12, 30, 0)
    msg = GoodmailIntegrationMailer.wrapped(
      to: "user@example.com",
      subject: "Custom headers",
      date: sent_at,
      "X-Correlation-ID" => "wrapped-123"
    ).message

    assert_equal sent_at.to_datetime, msg.date
    assert_equal "wrapped-123", msg["X-Correlation-ID"].value
  end

  def test_goodmail_mail_uses_custom_layout_path_without_leaking_the_header
    Tempfile.create(["goodmail-action-mailer-layout", ".erb"]) do |file|
      file.write("<html><body>MAILER-LAYOUT <%= body_html %></body></html>")
      file.flush

      msg = GoodmailIntegrationMailer.wrapped(
        to: "user@example.com",
        subject: "Custom layout",
        layout_path: file.path
      ).message

      assert_includes msg.html_part.body.decoded, "MAILER-LAYOUT"
      assert_includes msg.html_part.body.decoded, "Wrapped body"
      assert_nil msg["layout_path"]
    end
  end

  def test_goodmail_mail_applies_inline_attachments_and_pins_content_id
    msg = GoodmailIntegrationMailer.wrapped_inline(
      to: "user@example.com",
      subject: "Inline"
    ).message

    logo = msg.attachments.find { |attachment| attachment.filename == "logo.png" }

    refute_nil logo
    assert_predicate logo, :inline?
    assert_match(/\A<[0-9a-f]{24}\.logo\.png@inline\.goodmail\.invalid>\z/, logo.content_id)

    content_id = logo.content_id.delete_prefix("<").delete_suffix(">")

    assert_match(/<img[^>]+src="cid:#{Regexp.escape(content_id)}"/, msg.html_part.body.decoded)
  end

  def test_goodmail_mail_parts_supports_pre_rendered_custom_mailer_flows
    msg = GoodmailIntegrationMailer.pre_rendered(
      { to: "user@example.com", subject: "Rendered" },
      { subject: "Rendered", unsubscribe_url: "https://example.com/u" }
    ).message

    hero = msg.attachments.find { |attachment| attachment.filename == "hero.png" }

    refute_nil hero
    assert_predicate hero, :inline?
    assert_equal "<https://example.com/u>", msg["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", msg["List-Unsubscribe-Post"].value
  end

  def test_goodmail_mail_parts_can_resolve_unsubscribe_url_from_headers
    msg = GoodmailIntegrationMailer.pre_rendered_with_header_unsubscribe(
      to: "user@example.com",
      subject: "Header unsubscribe",
      unsubscribe_url: "https://example.com/header-u"
    ).message

    assert_nil msg["unsubscribe_url"]
    assert_equal "<https://example.com/header-u>", msg["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", msg["List-Unsubscribe-Post"].value
  end

  def test_goodmail_render_parts_evaluates_blocks_with_the_mailer_context
    msg = GoodmailIntegrationMailer.pre_rendered_context(
      to: "user@example.com",
      subject: "Pre-rendered context"
    ).message

    assert_includes msg.text_part.body.decoded, "Hello Avery"
    assert_includes msg.html_part.body.decoded, "https://example.test/accounts/42"
  end

  def test_goodmail_mail_parts_noops_for_legacy_parts_without_attachments
    msg = GoodmailIntegrationMailer.legacy_parts(
      to: "user@example.com",
      subject: "Legacy"
    ).message

    assert_empty msg.attachments
    assert_includes msg.text_part.body.decoded, "Legacy body"
    assert_includes msg.html_part.body.decoded, "Legacy body"
  end
end
