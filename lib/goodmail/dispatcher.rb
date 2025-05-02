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

      # 4. Render the HTML body using the Layout, passing unsubscribe URL
      html_body = Goodmail::Layout.render(
        builder.html_output,
        headers[:subject],
        unsubscribe_url: unsubscribe_url # Pass determined URL to layout renderer
      )

      # 5. Generate plaintext version
      text_body = generate_plaintext(builder.html_output)

      # 6. Slice standard headers for the mailer action
      #    We no longer need to exclude unsubscribe_url here, as the mailer
      #    doesn't use it directly in the mail() call anymore.
      mailer_headers = slice_mail_headers(headers)

      # 7. Build the mail object by calling the mailer action on the internal Mailer class.
      #    Pass the unsubscribe_url so the mailer can add the header internally.
      delivery_object = Goodmail::Mailer.compose_message(
        mailer_headers,
        html_body,
        text_body,
        unsubscribe_url # Pass URL to mailer action
      )

      # 8. Return the ActionMailer::MessageDelivery object
      #    (List-Unsubscribe header added inside compose_message)
      delivery_object
    end

    private

    # Whitelist standard headers to pass to ActionMailer's mail() method
    def slice_mail_headers(h)
      h.slice(:to, :from, :cc, :bcc, :reply_to, :subject)
    end

    # Removed add_list_unsubscribe_header - logic moved into Mailer#compose_message

    # Improved HTML tag stripper for plaintext generation.
    def generate_plaintext(html)
      text = html.dup
      # Decode entities early to handle tags like &lt; correctly before stripping
      text = CGI.unescapeHTML(text)
      # Convert links: Link Text ( URL )
      text.gsub!(%r{<a[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>}i) { "#{$2.strip} ( #{$1.strip} )" }
      # Replace block elements and <br> with double newlines for spacing
      text.gsub!(%r{</?(p|h[1-6]|ul|ol|li|div|tr|table|hr)[^>]*>}i, "\n\n")
      text.gsub!(%r{<br\s*/?>}i, "\n\n")
      # Strip any remaining HTML tags (<...>)
      text.gsub!(%r{<[^>]+?>}, "")
      # Normalize whitespace: replace multiple spaces/tabs with single space, trim lines
      text.gsub!(/[ \t]+/, " ")
      text = text.lines.map(&:strip).join("\n")
      # Compact multiple newlines down to a maximum of two
      text.gsub!(/[\n]{3,}/, "\n\n")
      text.strip # Final trim of leading/trailing whitespace
    end

  end
end
