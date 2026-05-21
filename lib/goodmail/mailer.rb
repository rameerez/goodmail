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
    def compose_message(
      headers,
      raw_html_body,
      unsubscribe_url,
      dsl_attachments = [],
      preheader: nil,
      render_config: nil
    )
      # `Goodmail.compose` renders the DSL/layout before returning an
      # ActionMailer::MessageDelivery, but Action Mailer does not run this
      # mailer action until `.message`, `.deliver_now`, or the delivery job
      # materializes it. Re-install the effective render config here so the
      # lazy action uses the same branding/footer settings as the already
      # rendered HTML body.
      # Sources:
      # - ActionMailer::MessageDelivery lazy processing:
      #   https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/message_delivery.rb#L19-L31
      # - Action Mailer deliver_later serializes only action arguments:
      #   https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/message_delivery.rb#L142-L155
      Goodmail.with_config(render_config) do
        compose_message_with_config(headers, raw_html_body, unsubscribe_url, dsl_attachments, preheader: preheader)
      end
    end

    private

    def compose_message_with_config(headers, raw_html_body, unsubscribe_url, dsl_attachments, preheader: nil)
      inlined_html = inline_css(raw_html_body)

      # The plaintext part runs through `Goodmail::Plaintext`, which
      # pre-processes the source HTML (strips MSO-only blocks + the
      # hidden preheader span) before Premailer extracts text. That's
      # what stops the button label from duplicating in plaintext and
      # the inbox-preview text from appearing as a phantom first line.
      generated_plain_text = Goodmail::Plaintext.generate(raw_html_body, preheader: preheader)

      goodmail_add_list_unsubscribe_headers!(headers, unsubscribe_url)
      goodmail_apply_attachments!(dsl_attachments)

      # Call the instance-level `mail` method
      mail(headers) do |format|
        # Use the premailer-generated plaintext
        format.text { render plain: generated_plain_text.strip }
        # Use the CSS-inlined HTML
        format.html { render html: inlined_html.html_safe }
      end
      # Action Mailer automatically returns the MessageDelivery object
    end

    def inline_css(raw_html_body)
      # The HTML part: Premailer inlines all the CSS that's inlinable
      # and leaves the residual @media query block in <style>. The
      # MSO conditional comments survive (we need them for Outlook's
      # VML button rendering).
      premailer = Premailer.new(
        raw_html_body,
        with_html_string: true,
        adapter: :nokogiri,
        preserve_styles: false, # Force inlining + remove the static rules from <style>
        remove_ids: true,
        remove_comments: false, # KEEP conditional comments so MSO/Outlook still work
        input_encoding: "UTF-8" # Defensive — see Goodmail::Plaintext for
                                # why custom layouts without `<meta
                                # charset>` would otherwise mangle every
                                # accented character.
      )
      premailer.to_inline_css
    end
  end
end
