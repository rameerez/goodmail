# frozen_string_literal: true
require "premailer"
require "cgi" # For unescaping HTML in plaintext generation (though Premailer might handle most)

module Goodmail
  # Simple struct to hold the rendered HTML and text parts of an email.
  EmailParts = Struct.new(:html, :text, keyword_init: true)

  # Renders the email content using the Goodmail DSL and returns HTML and text parts.
  # This method does not send the email but prepares its content for sending.
  #
  # @param headers [Hash] Mail headers. Expected to contain :subject.
  #                       Can also contain :unsubscribe_url and :preheader to override defaults.
  # @param dsl_block [Proc] Block containing Goodmail DSL calls (text, button, etc.)
  # @return [Goodmail::EmailParts] An object containing the :html and :text email parts.
  def self.render(headers = {}, &dsl_block)
    # 1. Initialize the Builder and execute the DSL block
    builder = Goodmail::Builder.new
    builder.instance_eval(&dsl_block) if block_given?
    core_html_content = builder.html_output

    # 2. Determine unsubscribe_url and preheader
    #    These are removed from headers as they are Goodmail-specific, not standard mail headers.
    current_headers = headers.dup # Avoid modifying the original headers hash directly
    unsubscribe_url = current_headers.delete(:unsubscribe_url) || Goodmail.config.unsubscribe_url
    preheader = current_headers.delete(:preheader) || Goodmail.config.default_preheader || current_headers[:subject]

    # 3. Render the raw HTML body using the Layout
    #    The subject is passed for the <title> tag and potentially other uses in layout.
    #    Unsubscribe URL and preheader are passed for inclusion in the layout.
    raw_html_body = Goodmail::Layout.render(
      core_html_content,
      current_headers[:subject], # Use subject from (potentially modified) current_headers
      unsubscribe_url: unsubscribe_url,
      preheader: preheader
    )

    # 4. Use Premailer to inline CSS and generate plaintext
    premailer = Premailer.new(
      raw_html_body,
      with_html_string: true,
      adapter: :nokogiri,
      preserve_styles: false, # Force inlining and remove <style> block
      remove_ids: true,       # Remove IDs
      remove_comments: false  # Keep MSO conditional comments
    )

    final_inlined_html = premailer.to_inline_css
    generated_plain_text = premailer.to_plain_text

    # 5. Perform refined plaintext cleanup (ported from Goodmail::Mailer)
    # 5.1. Remove logo alt text line (if logo exists and has associated URL)
    if Goodmail.config.logo_url.present? && Goodmail.config.company_url.present? && Goodmail.config.company_name.present?
      company_name_escaped = Regexp.escape(Goodmail.config.company_name)
      company_url_escaped = Regexp.escape(Goodmail.config.company_url)
      # Regex to match the typical alt text pattern for a linked logo image
      logo_alt_pattern = /^\s*#{company_name_escaped}\s+Logo\s*\(.*?#{company_url_escaped}.*?\).*\n?/i
      generated_plain_text.gsub!(logo_alt_pattern, "")
    end

    # 5.2. Remove any remaining standalone URL lines (often from logo links or similar artifacts)
    # This targets lines that consist *only* of a URL.
    generated_plain_text.gsub!(/^\s*https?:\/\/\S+\s*$\n?/i, "")

    # 5.3. Compact excess blank lines (more than two consecutive newlines)
    generated_plain_text.gsub!(/\n{3,}/, "\n\n")

    # 6. Return the structured parts
    EmailParts.new(html: final_inlined_html, text: generated_plain_text.strip)
  end
end
