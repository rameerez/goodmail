# frozen_string_literal: true
require_relative "../test_helper"

class GoodmailTopLevelTest < Minitest::Test
  def setup
    ActionMailer::Base.deliveries.clear
  end

  def test_compose_returns_message_delivery_and_can_deliver
    delivery = Goodmail.compose(to: "u@example.com", from: "noreply@example.com", subject: "Hello") do
      h1 "Welcome"
      text "Body"
    end
    assert_kind_of ActionMailer::MessageDelivery, delivery
    mail = delivery.deliver_now
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal "Hello", mail.subject
    assert_includes mail.html_part.decoded, "Welcome"
    assert_includes mail.text_part.decoded, "Body"
  end
end