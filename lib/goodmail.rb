# frozen_string_literal: true

# Order matters: Load dependencies and base modules first.
require "action_mailer"
require "ostruct"

# Load Goodmail components
require_relative "goodmail/version"
require_relative "goodmail/configuration"
require_relative "goodmail/error" # Load Error class explicitly if needed elsewhere
require_relative "goodmail/builder"
require_relative "goodmail/layout"
require_relative "goodmail/email"
require_relative "goodmail/mailer"     # Require the internal Mailer
require_relative "goodmail/dispatcher"

# The main namespace for the Goodmail gem.
# Provides configuration and the primary .compose method.
module Goodmail
  # Extend self with Configuration module methods (config, configure, reset_config!)
  extend Configuration

  # Composes a Mail::Message object using the Goodmail DSL and layout.
  #
  # This is the primary entry point for creating emails with Goodmail.
  # The returned Mail::Message object can then have `.deliver_now` or
  # `.deliver_later` called on it.
  #
  # @param headers [Hash] Mail headers (:to, :from, :subject, etc.)
  #                       Also accepts :unsubscribe (true or String URL).
  # @param block [Proc] Block containing Goodmail DSL calls (text, button, etc.)
  # @return [Mail::Message] The generated Mail object, ready for delivery.
  #
  # @example
  #   mail = Goodmail.compose(to: 'user@example.com', subject: 'Hello!') do
  #     text "This is the email body."
  #     button "Click Me", "https://example.com"
  #   end
  #
  #   mail.deliver_now
  #   # or
  #   mail.deliver_later
  #
  def self.compose(headers = {}, &block)
    # Delegate the actual building process to the Dispatcher
    Dispatcher.build_message(headers, &block)
  end

  # Error class is defined in lib/goodmail/error.rb
end
