# frozen_string_literal: true
require_relative "../test_helper"

class GoodmailMailerTest < Minitest::Test
  def setup
    ActionMailer::Base.deliveries.clear
    Goodmail.reset_config!
    Goodmail.configure do |c|
      c.company_name = "Acme Inc."
      c.brand_color = "#123456"
      c.logo_url = nil
      c.company_url = nil
      c.unsubscribe_url = nil
      c.default_preheader = nil
      c.footer_text = nil
      c.show_footer_unsubscribe_link = false
    end
  end

  def test_compose_message_generates_text_and_html_and_respects_list_unsubscribe
    headers = { to: "u@example.com", from: "noreply@example.com", subject: "S" }
    raw_html = Goodmail::Layout.render("<p>Body</p>", "S", preheader: "P")
    mail_message = Goodmail::Mailer.new.compose_message(headers, raw_html, nil, "https://unsub")
    assert_kind_of Mail::Message, mail_message
    assert_equal "<https://unsub>", mail_message["List-Unsubscribe"].to_s

    # multipart with text and html
    assert mail_message.multipart?
    html_part = mail_message.html_part
    text_part = mail_message.text_part
    refute_nil html_part
    refute_nil text_part
    assert_includes html_part.decoded, "<html"
    assert_match(/Body/, text_part.decoded)
  end

  def test_list_unsubscribe_header_not_added_when_blank
    headers = { to: "u@example.com", from: "noreply@example.com", subject: "S" }
    raw_html = Goodmail::Layout.render("<p>Body</p>", "S")
    mail = Goodmail::Mailer.new.compose_message(headers, raw_html, nil, "  ")
    refute_includes mail.header.fields.map(&:name), "List-Unsubscribe"
  end

  def test_plaintext_cleanup_strips_url_only_lines_and_compacts
    Goodmail.configure do |c|
      c.logo_url = "https://cdn/logo.png"
      c.company_url = "https://company.example"
    end
    headers = { to: "u@example.com", from: "noreply@example.com", subject: "S" }
    raw_html = Goodmail::Layout.render("<img src=\"https://cdn/logo.png\" alt=\"Acme Inc. Logo\"><p>Hello</p>", "S")
    mail = Goodmail::Mailer.new.compose_message(headers, raw_html, nil, nil)
    assert mail.multipart?
    text_body = mail.text_part.decoded
    refute_match(/^\s*https?:\/\//i, text_body)
    refute_includes text_body, "\n\n\n"
    assert_includes text_body, "Hello"
  end
end