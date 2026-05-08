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
    def compose_message(headers, raw_html_body, _raw_text_body, unsubscribe_url, dsl_attachments = [], preheader: nil)
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
      inlined_html = premailer.to_inline_css

      # The plaintext part runs through `Goodmail::Plaintext`, which
      # pre-processes the source HTML (strips MSO-only blocks + the
      # hidden preheader span) before Premailer extracts text. That's
      # what stops the button label from duplicating in plaintext and
      # the inbox-preview text from appearing as a phantom first line.
      generated_plain_text = Goodmail::Plaintext.generate(raw_html_body, preheader: preheader)

      # Add List-Unsubscribe + List-Unsubscribe-Post headers *before* calling
      # `mail()`. RFC 8058 introduced the one-click HTTPS unsubscribe flow,
      # and Gmail / Yahoo's Feb 2024 sender requirements made this header
      # pair mandatory for bulk senders to avoid "unsubscribe is missing"
      # being treated as a spam signal. The recipient's mail client posts
      # the magic body `List-Unsubscribe=One-Click` to the URL when the
      # user clicks "Unsubscribe" inline.
      #
      # Sources:
      #   - RFC 8058 §3.1 (HTTPS one-click body):
      #     https://www.rfc-editor.org/rfc/rfc8058#section-3.1
      #   - Gmail bulk sender guidelines (one-click unsubscribe is required
      #     for senders averaging over 5k messages/day to gmail.com):
      #     https://support.google.com/mail/answer/81126
      #   - Yahoo "Sender Best Practices" (matching requirements):
      #     https://senders.yahooinc.com/best-practices/
      if unsubscribe_url.is_a?(String) && !unsubscribe_url.strip.empty?
        headers["List-Unsubscribe"] = "<#{unsubscribe_url.strip}>"
        # The Post header tells well-behaved mail clients (Gmail, Apple
        # Mail, Outlook) that they may POST the one-click body directly
        # to the URL, avoiding the round-trip through the user's browser.
        # Senders that don't yet implement the POST endpoint should still
        # set this header — Gmail simply falls back to opening the URL.
        headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
      end

      # Apply DSL-collected attachments to the mailer's attachments hash.
      # Action Mailer's `attachments[]=` and `attachments.inline[]=` are the
      # only documented ways to attach binary parts to the outgoing message;
      # we route DSL `attach` calls through here so the Builder block can
      # stay free of Mailer-internal references.
      # Source: https://guides.rubyonrails.org/action_mailer_basics.html#sending-email-with-attachments
      Array(dsl_attachments).each do |attachment|
        target = attachment[:inline] ? attachments.inline : attachments
        if attachment[:mime_type].to_s.strip.empty?
          target[attachment[:filename]] = attachment[:content]
        else
          target[attachment[:filename]] = {
            mime_type: attachment[:mime_type],
            content: attachment[:content]
          }
        end

        # Pin the inline part's `Content-ID` to the filename so that
        # `inline_image("logo.png", ...)` (which emits `<img
        # src="cid:logo.png">` in the body) resolves to THIS part. By
        # default, Mail gem auto-generates a globally-unique Content-ID
        # of the shape `<longhash@host.tld.mail>` — that makes the
        # body's `cid:logo.png` reference dangle and the image renders
        # as a broken-icon in every email client.
        #
        # Sources:
        #   - RFC 2392 (CID URLs reference the part's Content-ID
        #     header): https://www.rfc-editor.org/rfc/rfc2392
        #   - Mail::Part#content_id setter:
        #     https://github.com/mikel/mail/blob/master/lib/mail/parts_list.rb
        #     (mail gem auto-assigns CIDs when none is set; passing one
        #     overrides the default).
        if attachment[:inline]
          # `attachments[filename]` returns the Mail::Part regardless
          # of whether it was added to `attachments` or
          # `attachments.inline`, so we can address it uniformly here.
          attachments[attachment[:filename]].content_id = "<#{attachment[:filename]}>"
        end
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
