# frozen_string_literal: true
require "action_mailer"

module Goodmail
  # Internal Mailer class.
  # Inherits from ActionMailer::Base to provide the necessary context
  # for building Mail::Message objects, but without relying on any
  # host application views or layouts.
  class Mailer < ActionMailer::Base
    # No explicit default settings needed here usually,
    # as headers (:from, etc.) should be provided in Goodmail.compose
    # It will, however, inherit default ActionMailer settings from the Rails app
    # (like delivery_method, smtp_settings, default_url_options) which is good.

    # This instance method acts as the mailer action.
    # It's called via Goodmail::Mailer.compose_message(...)
    # Action Mailer wraps the result in a MessageDelivery object.
    # @api internal
    def compose_message(headers, html_body, text_body)
      # Call the instance-level `mail` method provided by ActionMailer::Base
      mail(headers) do |format|
        format.text { render plain: text_body }
        format.html { render html: html_body.html_safe }
      end
    end
  end
end
