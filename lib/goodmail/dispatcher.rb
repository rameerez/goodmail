# frozen_string_literal: true
require "action_mailer"
require "cgi" # For unescaping HTML in plaintext generation
require_relative "mailer" # Require the internal mailer

module Goodmail
  # Responsible for orchestrating the building of the Mail::Message object.
  module Dispatcher
    extend self

    # Builds the Mail::Message object with HTML and Text parts, wrapped in
    # an ActionMailer::MessageDelivery object.
    # @api private
    def build_message(headers, &block)
      # 1. Initialize the Builder
      builder = Goodmail::Builder.new

      # 2. Execute the DSL block within the Builder instance
      builder.instance_eval(&block) if block_given?

      # 3. Determine the final unsubscribe URL (user-provided)
      unsubscribe_url = headers[:unsubscribe_url] || Goodmail.config.unsubscribe_url

      # 4. Determine preheader text (priority: header > config > subject)
      preheader = headers[:preheader] || Goodmail.config.default_preheader || headers[:subject]

      # 5. Render the raw HTML body using the Layout
      raw_html_body = Goodmail::Layout.render(
        builder.html_output,
        headers[:subject],
        unsubscribe_url: unsubscribe_url,
        preheader: preheader # Pass preheader to layout
      )

      # 6. Slice standard headers for the mailer action
      mailer_headers = slice_mail_headers(headers)

      # 7. Build the mail object via the internal Mailer class action.
      delivery_object = Goodmail::Mailer.compose_message(
        mailer_headers,
        raw_html_body,
        nil, # Pass nil for raw_text_body - Premailer generates it
        unsubscribe_url
      )

      # 8. Return the ActionMailer::MessageDelivery object
      delivery_object
    end

    private

    # Whitelist standard headers to pass to ActionMailer's mail() method
    # Excludes custom headers like :unsubscribe_url, :preheader
    def slice_mail_headers(h)
      h.slice(:to, :from, :cc, :bcc, :reply_to, :subject)
    end

    # Removed generate_plaintext - now handled by Premailer in Mailer#compose_message
  end
end
