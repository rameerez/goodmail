# frozen_string_literal: true
require "premailer"
require "cgi" # For unescaping HTML in plaintext generation (though Premailer might handle most)

module Goodmail
  # Simple struct to hold the rendered HTML and text parts of an email, plus
  # any attachments collected via the `attach` / `inline_image` DSL helpers.
  # Custom Action Mailer classes can call Goodmail's auto-installed
  # `goodmail_mail_parts(parts, headers)` helper to apply attachments, pin
  # inline Content-IDs, add unsubscribe headers, and send the multipart body.
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
  #                       Can also contain :unsubscribe_url, :preheader, :locale,
  #                       :context, :config, and :layout_path to override
  #                       render-only behavior.
  # @param dsl_block [Proc] Block containing Goodmail DSL calls (text, button, etc.)
  # @return [Goodmail::EmailParts] An object containing the :html and :text email parts.
  def self.render(headers = {}, &dsl_block)
    # 1. Initialize the Builder and execute the DSL block
    current_headers = headers.dup # Avoid modifying the original headers hash directly
    context = render_header_value!(current_headers, :context)
    locale = render_header_value!(current_headers, :locale)
    render_config = render_header_value!(current_headers, :config)
    render_config = render_header_value!(current_headers, :configuration) if render_config.nil?
    layout_path = render_header_value!(current_headers, :layout_path)

    Goodmail.with_config(render_config) do
      builder = Goodmail::Builder.new(context: context)
      evaluate_builder_dsl(builder, locale, &dsl_block)
      core_html_content = builder.html_output

      # 2. Determine unsubscribe_url and preheader
      #    These are removed from headers as they are Goodmail-specific, not standard mail headers.
      unsubscribe_url = current_headers.delete(:unsubscribe_url) || Goodmail.config.unsubscribe_url
      preheader = current_headers.delete(:preheader) || Goodmail.config.default_preheader || current_headers[:subject]

      # 3. Render the raw HTML body using the Layout
      #    The subject is passed for the <title> tag and potentially other uses in layout.
      #    Unsubscribe URL and preheader are passed for inclusion in the layout.
      raw_html_body = Goodmail::Layout.render(
        core_html_content,
        current_headers[:subject], # Use subject from (potentially modified) current_headers
        layout_path: layout_path,
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

  def self.render_header_value!(headers, key)
    value = headers.delete(key)
    value = headers.delete(key.to_s) if value.nil? && headers.key?(key.to_s)
    value
  end
  private_class_method :render_header_value!

  def self.evaluate_builder_dsl(builder, locale, &dsl_block)
    return unless block_given?

    render_block = proc { builder.instance_eval(&dsl_block) }
    if !locale.nil? && !locale.to_s.empty? && defined?(I18n)
      I18n.with_locale(locale, &render_block)
    else
      render_block.call
    end
  end
  private_class_method :evaluate_builder_dsl
end
