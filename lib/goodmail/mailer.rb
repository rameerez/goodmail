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
    def compose_message(headers, raw_html_body, _raw_text_body, unsubscribe_url)
      # Initialize Premailer with the raw HTML body from the layout
      premailer = Premailer.new(
        raw_html_body,
        with_html_string: true,
        # Common options:
        adapter: :nokogiri,
        preserve_styles: false, # Set to false to force inlining *and* remove <style> block
        remove_ids: true, # Can usually remove IDs
        remove_comments: false, # KEEP conditional comments so MSO conditionals in the template work!
        # Note: `plain_text_images: false` might exist but is not standard;
        # relying on gsub cleanup below.
      )

      # Get processed content
      inlined_html = premailer.to_inline_css
      # Generate plain text, skipping image conversion
      generated_plain_text = premailer.to_plain_text

      # Clean up plaintext:
      # 1. Remove logo alt text line (if logo exists and has associated URL)
      if Goodmail.config.logo_url.present? && Goodmail.config.company_url.present? && Goodmail.config.company_name.present?
        company_name_escaped = Regexp.escape(Goodmail.config.company_name)
        company_url_escaped = Regexp.escape(Goodmail.config.company_url)
        logo_alt_pattern = /^\s*#{company_name_escaped}\s+Logo\s+\(.*?#{company_url_escaped}.*?\).*\n?/i
        generated_plain_text.gsub!(logo_alt_pattern, '')
      end
      # 2. Remove any remaining standalone URL lines (often from logo links)
      generated_plain_text.gsub!(/^\s*https?:\/\/\S+\s*$\n?/i, '')
      # 3. Compact excess blank lines created by gsubbing
      generated_plain_text.gsub!(/\n{3,}/, "\n\n")

      # Add List-Unsubscribe header to the headers hash *before* calling mail()
      if unsubscribe_url.is_a?(String) && !unsubscribe_url.strip.empty?
        headers["List-Unsubscribe"] = "<#{unsubscribe_url.strip}>"
      end

      # Call the instance-level `mail` method
      mail(headers) do |format|
        # Use the premailer-generated plaintext
        format.text { render plain: generated_plain_text.strip }
        # Use the CSS-inlined HTML
        format.html { render html: inlined_html.html_safe }
      end
      # Action Mailer automatically returns the MessageDelivery object
    end
  end
end
