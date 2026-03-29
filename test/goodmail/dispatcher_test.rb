# frozen_string_literal: true
require_relative "../test_helper"

class GoodmailDispatcherTest < Minitest::Test
  def setup
    ActionMailer::Base.deliveries.clear
    Goodmail.reset_config!
    Goodmail.configure do |c|
      c.company_name = "Acme Inc."
      c.unsubscribe_url = nil
      c.default_preheader = nil
    end
  end

  def test_build_message_returns_message_delivery
    delivery = Goodmail::Dispatcher.build_message({ to: "u@example.com", from: "noreply@example.com", subject: "S" }) do
      text "Hello"
    end
    assert_kind_of ActionMailer::MessageDelivery, delivery
    mail = delivery.message
    assert_equal ["u@example.com"], mail.to
    assert_equal ["noreply@example.com"], mail.from
    assert_equal "S", mail.subject
  end

  def test_custom_headers_are_not_passed_to_mailer_mail
    delivery = Goodmail::Dispatcher.build_message({ to: "u@example.com", from: "noreply@example.com", subject: "S", unsubscribe_url: "https://u", preheader: "P" }) do
      text "Hello"
    end
    mail = delivery.message
    refute_includes mail.header.fields.map(&:name), "unsubscribe_url"
    refute_includes mail.header.fields.map(&:name), "preheader"
  end
end