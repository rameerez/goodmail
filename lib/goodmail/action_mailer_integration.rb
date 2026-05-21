# frozen_string_literal: true

require "uri"

module Goodmail
  LIST_UNSUBSCRIBE_HEADER = "List-Unsubscribe"
  LIST_UNSUBSCRIBE_POST_HEADER = "List-Unsubscribe-Post"
  LIST_UNSUBSCRIBE_ONE_CLICK_VALUE = "List-Unsubscribe=One-Click"
  GOODMAIL_RENDER_HEADER_KEYS = %i[
    preheader
    unsubscribe_url
    locale
    context
    config
    configuration
    layout_path
  ].freeze

  # Returns the deliverability headers for a configured unsubscribe URL.
  #
  # RFC 8058 one-click unsubscribe is only eligible for HTTPS
  # List-Unsubscribe URLs and uses the exact `List-Unsubscribe=One-Click`
  # POST body. Keep the classic List-Unsubscribe header for other non-blank
  # values, but don't advertise one-click POST support unless the URL qualifies.
  #
  # Sources:
  #   - RFC 8058 §3.1:
  #     https://www.rfc-editor.org/rfc/rfc8058#section-3.1
  #   - Gmail sender guidelines:
  #     https://support.google.com/mail/answer/81126
  #   - Yahoo sender best practices:
  #     https://senders.yahooinc.com/best-practices/
  def self.list_unsubscribe_headers(unsubscribe_url)
    return {} unless unsubscribe_url.is_a?(String)

    stripped_url = unsubscribe_url.strip
    return {} if stripped_url.empty?

    headers = { LIST_UNSUBSCRIBE_HEADER => "<#{stripped_url}>" }
    if one_click_unsubscribe_url?(stripped_url)
      headers[LIST_UNSUBSCRIBE_POST_HEADER] = LIST_UNSUBSCRIBE_ONE_CLICK_VALUE
    end
    headers
  end

  def self.one_click_unsubscribe_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty?
  rescue URI::InvalidURIError
    false
  end

  # Returns the header hash Goodmail should hand to Action Mailer's `mail`.
  # Rails intentionally accepts arbitrary message headers and filters only
  # framework-only render keys internally; Goodmail should follow that shape
  # instead of maintaining a narrow whitelist of envelope fields.
  # Source:
  # https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/base.rb#L972-L976
  def self.action_mailer_headers(headers)
    headers.each_with_object({}) do |(key, value), result|
      next if render_header_key?(key)

      result[key] = value
    end
  end

  def self.render_header_key?(key)
    GOODMAIL_RENDER_HEADER_KEYS.include?(key) ||
      (key.is_a?(String) && GOODMAIL_RENDER_HEADER_KEYS.include?(key.to_sym))
  end

  # Installs Goodmail's mailer helpers once on ActionMailer::Base so app
  # mailers, Devise mailers, Pay mailers, and other custom Action Mailer
  # subclasses can call `goodmail_mail` without per-class include glue.
  #
  # The helper methods stay private because Action Mailer dispatches mailer
  # actions through `action_methods`; keeping the API private prevents Rails
  # from treating helpers as deliverable actions.
  # Source:
  # https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/base.rb#L614-L618
  def self.install_action_mailer_integration!(base = ActionMailer::Base)
    return if base < ActionMailerIntegration

    base.include(ActionMailerIntegration)
  end

  # Private helpers for Action Mailer classes that use `Goodmail.render` and
  # then call `mail()` themselves. Goodmail installs this module into
  # ActionMailer::Base at load time; apps should not need to include it.
  module ActionMailerIntegration
    DEFAULT_UNSUBSCRIBE_URL = Object.new.freeze

    private

    # High-level wrapper for the common custom-mailer path:
    #
    #   goodmail_mail(to: user.email, subject: "Hello", preheader: "...") do
    #     text "Body"
    #   end
    #
    # Goodmail-specific keys (`:preheader`, `:unsubscribe_url`) are passed to
    # `Goodmail.render` and stripped before calling Action Mailer's `mail()`.
    # Attachments and inline CIDs are applied before the final `mail()` call
    # because Rails rejects attachment writes after `mail` has materialized the
    # message.
    # Sources:
    # - `mail` creates parts and finalizes content type:
    #   https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/base.rb#L875-L907
    # - late attachments raise:
    #   https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/base.rb#L766-L781
    def goodmail_mail(
      mail_headers = {},
      render_options: nil,
      unsubscribe_url: DEFAULT_UNSUBSCRIBE_URL,
      **headers,
      &block
    )
      raise ArgumentError, "goodmail_mail requires a block" unless block_given?

      mail_headers = mail_headers.merge(headers)
      render_headers = goodmail_render_options(mail_headers, render_options)
      render_config = goodmail_render_config(render_headers)

      Goodmail.with_config(render_config) do
        resolved_unsubscribe_url = goodmail_resolve_unsubscribe_url(
          mail_headers,
          render_headers,
          unsubscribe_url
        )
        render_headers[:unsubscribe_url] = resolved_unsubscribe_url if goodmail_present?(resolved_unsubscribe_url)
        # Preserve the Action Mailer instance as Goodmail's render context so
        # DSL blocks can still read mailer ivars and helper methods even though
        # Goodmail evaluates them on its Builder receiver.
        # Source:
        # https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/README.rdoc#L36-L45
        render_headers[:context] = self unless goodmail_header_key?(render_headers, :context)

        parts = goodmail_render_parts(render_headers, &block)
        goodmail_mail_parts(parts, mail_headers, unsubscribe_url: resolved_unsubscribe_url)
      end
    end

    # Context-aware render helper for mailers that truly need to render first
    # and inspect or mutate generated parts before calling `mail()` later.
    # It injects the current mailer as the Goodmail render context so app code
    # does not need to repeat `Goodmail.render(..., context: self)` everywhere.
    # Source:
    # https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/README.rdoc#L36-L45
    def goodmail_render_parts(render_options = {}, **headers, &block)
      raise ArgumentError, "goodmail_render_parts requires a block" unless block_given?

      render_headers = render_options.merge(headers)
      render_headers[:context] = self unless goodmail_header_key?(render_headers, :context)

      Goodmail.render(render_headers, &block)
    end

    # Lower-level wrapper for apps that must call `Goodmail.render` separately
    # but still want Goodmail to own the mechanical Action Mailer handoff. This
    # stays inside the mailer method, so Action Mailer's lazy `MessageDelivery`
    # and `deliver_later` serialization model remain intact.
    # Source:
    # https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/message_delivery.rb#L142-L155
    def goodmail_mail_parts(parts, mail_headers = {}, unsubscribe_url: DEFAULT_UNSUBSCRIBE_URL, **headers)
      goodmail_apply_parts!(parts)

      mail_headers = mail_headers.merge(headers)
      final_headers = goodmail_mail_headers(mail_headers)
      resolved_unsubscribe_url = goodmail_resolve_unsubscribe_url(
        mail_headers,
        {},
        unsubscribe_url
      )
      goodmail_add_list_unsubscribe_headers!(final_headers, resolved_unsubscribe_url)

      # Rails' documented block form builds explicit text/html responses via
      # ActionMailer::Collector and then lets `mail` assemble the MIME tree.
      # Sources:
      # - block-form `mail`: https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/base.rb#L851-L873
      # - collector response body: https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/collector.rb#L25-L29
      mail(final_headers) do |format|
        format.text { render plain: parts.text.to_s }
        format.html { render html: parts.html.to_s.html_safe }
      end
    end

    # Applies `Goodmail.render(...).attachments` to Action Mailer's attachment
    # collection. Old Goodmail versions returned only html/text, so a missing
    # `attachments` method is a no-op for compatibility with older apps.
    def goodmail_apply_parts!(parts)
      return parts unless parts.respond_to?(:attachments)

      goodmail_apply_attachments!(parts.attachments)
      parts
    end

    def goodmail_apply_attachments!(attachment_descriptors)
      Array(attachment_descriptors).each do |attachment|
        # Use Action Mailer's public attachment APIs. Rails chooses the final
        # MIME container afterwards (`multipart/related` for inline-only,
        # `multipart/mixed` plus nested related parts for mixed attachments).
        # Source:
        # https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/base.rb#L1024-L1042
        target = attachment[:inline] ? attachments.inline : attachments
        payload =
          if attachment[:mime_type].to_s.strip.empty?
            attachment[:content]
          else
            { mime_type: attachment[:mime_type], content: attachment[:content] }
          end
        target[attachment[:filename]] = payload

        next unless attachment[:inline]

        # `inline_image` emits `<img src="cid:GENERATED_ID">` before Action
        # Mailer materializes the part. Pin the Mail::Part to that generated
        # Content-ID so RFC 2392 `cid:` resolution lands on this exact part.
        # Rails' preview interceptor also resolves `cid:` URLs by matching
        # against attachment CIDs, so this keeps previews and deliveries aligned.
        # Sources:
        # - RFC 2392: https://www.rfc-editor.org/rfc/rfc2392
        # - Rails CID preview lookup:
        #   https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/inline_preview_interceptor.rb#L33-L57
        content_id = attachment[:content_id].to_s.strip
        content_id = attachment[:filename].to_s if content_id.empty?
        attachments[attachment[:filename]].content_id = "<#{content_id}>"
      end
    end

    def goodmail_add_list_unsubscribe_headers!(headers, unsubscribe_url)
      headers.merge!(Goodmail.list_unsubscribe_headers(unsubscribe_url))
    end

    def goodmail_list_unsubscribe_headers(unsubscribe_url)
      Goodmail.list_unsubscribe_headers(unsubscribe_url)
    end

    def goodmail_render_options(mail_headers, render_options)
      render_headers = {}
      if goodmail_header_key?(mail_headers, :subject)
        render_headers[:subject] = goodmail_header_value(mail_headers, :subject)
      end
      render_headers.merge!(render_options || {})

      GOODMAIL_RENDER_HEADER_KEYS.each do |key|
        next if render_headers.key?(key) || !goodmail_header_key?(mail_headers, key)

        render_headers[key] = goodmail_header_value(mail_headers, key)
      end

      render_headers
    end

    def goodmail_mail_headers(mail_headers)
      Goodmail.action_mailer_headers(mail_headers)
    end

    def goodmail_resolve_unsubscribe_url(mail_headers, render_headers, unsubscribe_url)
      return unsubscribe_url unless unsubscribe_url.equal?(DEFAULT_UNSUBSCRIBE_URL)
      return render_headers[:unsubscribe_url] if render_headers.key?(:unsubscribe_url)
      if goodmail_header_key?(mail_headers, :unsubscribe_url)
        return goodmail_header_value(mail_headers, :unsubscribe_url)
      end

      Goodmail.config.unsubscribe_url
    end

    def goodmail_header_key?(headers, key)
      headers.key?(key) || headers.key?(key.to_s)
    end

    def goodmail_header_value(headers, key)
      headers.key?(key) ? headers[key] : headers[key.to_s]
    end

    def goodmail_render_config(headers)
      return goodmail_header_value(headers, :config) if goodmail_header_key?(headers, :config)

      goodmail_header_value(headers, :configuration) if goodmail_header_key?(headers, :configuration)
    end

    def goodmail_present?(value)
      !value.nil? && (!value.respond_to?(:empty?) || !value.empty?)
    end
  end
end
