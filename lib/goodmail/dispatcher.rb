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
    # This method is intended to be called internally by Goodmail.compose
    # @api private
    def build_message(headers, &block)
      # 1. Initialize the Builder
      builder = Goodmail::Builder.new

      # 2. Execute the DSL block within the Builder instance
      builder.instance_eval(&block) if block_given?

      # 3. Render the HTML body using the Layout
      html_body = Goodmail::Layout.render(builder.html_output, headers[:subject])

      # 4. Generate a plaintext version from the Builder's raw HTML output
      #    (before it's put into the layout)
      text_body = generate_plaintext(builder.html_output)

      # 5. Slice the headers we pass to the mailer action
      mailer_headers = slice_mail_headers(headers)

      # 6. Build the mail object by calling the mailer action on the internal Mailer class.
      delivery_object = Goodmail::Mailer.compose_message(mailer_headers, html_body, text_body)

      # 7. Add List-Unsubscribe header if requested (needs full headers)
      add_list_unsubscribe(delivery_object.message, headers)

      # 8. Return the ActionMailer::MessageDelivery object
      delivery_object
    end

    private

    # Whitelist headers to pass to ActionMailer for the main mail() call
    def slice_mail_headers(h)
      h.slice(:to, :from, :cc, :bcc, :reply_to, :subject)
    end

    # Adds the List-Unsubscribe header using the original full headers hash.
    def add_list_unsubscribe(mail, headers)
      unsubscribe_setting = headers[:unsubscribe]
      return unless unsubscribe_setting
      message = mail.is_a?(Mail::Message) ? mail : mail.try(:message)
      return unless message # Safety check

      unsubscribe_url = case unsubscribe_setting
                        when true then generate_unsubscribe_url(headers[:to])
                        when String then unsubscribe_setting
                        else nil
                        end
      return unless unsubscribe_url
      message.header["List-Unsubscribe"] = "<#{unsubscribe_url}>"
    end

    # Generates a default unsubscribe URL.
    def generate_unsubscribe_url(recipient)
      recipient_email = Array(recipient).first
      return nil unless recipient_email
      url_helpers_defined = defined?(Rails.application.routes.url_helpers)
      mailer_opts_defined = defined?(Rails.application.config.action_mailer.default_url_options)
      if url_helpers_defined && mailer_opts_defined
        host = Rails.application.config.action_mailer.default_url_options[:host]
        protocol = Rails.application.config.action_mailer.default_url_options[:protocol] || 'http'
        if host && Rails.application.routes.url_helpers.respond_to?(:unsubscribe_email_url)
          begin
            return Rails.application.routes.url_helpers.unsubscribe_email_url(recipient_email, host: host, protocol: protocol)
          rescue ArgumentError, NoMethodError => e
            warn "[Goodmail] WARN: Failed to generate unsubscribe URL with unsubscribe_email_url: #{e.message}. Falling back to config.base_url."
          end
        else
          warn "[Goodmail] WARN: Cannot generate unsubscribe URL via helpers (check route/host). Falling back to config.base_url."
        end
      end
      File.join(Goodmail.config.base_url, "emails/unsubscribe", CGI.escape(recipient_email))
    end

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
