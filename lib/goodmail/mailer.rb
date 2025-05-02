# frozen_string_literal: true
require "action_mailer"
require "premailer" # Require premailer library

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
    # It uses Premailer to inline CSS and generate plaintext.
    # @api internal
    def compose_message(headers, raw_html_body, raw_text_body, unsubscribe_url)
      # Initialize Premailer with the raw HTML body from the layout
      premailer = Premailer.new(
        raw_html_body,
        with_html_string: true,
        # Common options:
        adapter: :nokogiri, # Faster parser
        preserve_styles: true, # Keep <style> block for clients that support it
        remove_ids: false, # Keep IDs if needed for anchors etc.
        remove_comments: true
      )

      # Get processed content
      inlined_html = premailer.to_inline_css
      generated_plain_text = premailer.to_plain_text

      # Add List-Unsubscribe header to the headers hash *before* calling mail()
      if unsubscribe_url.is_a?(String) && !unsubscribe_url.strip.empty?
        headers["List-Unsubscribe"] = "<#{unsubscribe_url.strip}>"
      end

      # Call the instance-level `mail` method
      mail(headers) do |format|
        # Use the premailer-generated plaintext
        format.text { render plain: generated_plain_text }
        # Use the CSS-inlined HTML
        format.html { render html: inlined_html.html_safe }
      end
      # Action Mailer automatically returns the MessageDelivery object
    end
  end
end
