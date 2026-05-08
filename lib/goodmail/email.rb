# frozen_string_literal: true
require "premailer"
require "cgi" # For unescaping HTML in plaintext generation (though Premailer might handle most)

module Goodmail
  # Simple struct to hold the rendered HTML and text parts of an email,
  # plus any attachments collected via the `attach` / `inline_image` DSL
  # helpers. Callers using `Goodmail.render` (typically a custom mailer
  # subclass that wants to call `mail()` itself) can fan attachments out
  # to ActionMailer's `attachments` hash with a small loop:
  #
  #   parts.attachments.each do |a|
  #     target = a[:inline] ? attachments.inline : attachments
  #     target[a[:filename]] = a[:mime_type] ? { mime_type: a[:mime_type], content: a[:content] } : a[:content]
  #   end
  #
  # `attachments` defaults to `[]` for backwards compatibility — callers
  # written against 0.3.x keep working unchanged.
  EmailParts = Struct.new(:html, :text, :attachments, keyword_init: true) do
    def initialize(html: nil, text: nil, attachments: [])
      super(html: html, text: text, attachments: attachments || [])
    end
  end

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

    # 4. Run Premailer for CSS inlining (HTML part). Plaintext goes
    #    through `Goodmail::Plaintext` which pre-processes the source
    #    HTML to neutralize MSO-only markup and the hidden preheader
    #    span — both of which Premailer's plaintext extractor would
    #    otherwise leak into the text body.
    premailer = Premailer.new(
      raw_html_body,
      with_html_string: true,
      adapter: :nokogiri,
      preserve_styles: false, # Force inlining and remove <style> block
      remove_ids: true,       # Remove IDs
      remove_comments: false, # Keep MSO conditional comments in HTML
      input_encoding: "UTF-8" # See Goodmail::Plaintext for the full
                              # rationale — short version: Premailer
                              # double-encodes accented characters when
                              # the source has no <meta charset>.
    )
    final_inlined_html = premailer.to_inline_css
    final_plain_text = Goodmail::Plaintext.generate(raw_html_body, preheader: preheader)

    # 5. Return the structured parts
    EmailParts.new(
      html: final_inlined_html,
      text: final_plain_text,
      attachments: builder.attachments
    )
  end
end
