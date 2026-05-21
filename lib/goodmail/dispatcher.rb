# frozen_string_literal: true
require "action_mailer"
require "cgi" # For unescaping HTML in plaintext generation
require_relative "mailer" # Require the internal mailer

module Goodmail
  # Responsible for orchestrating the building of the Action Mailer delivery.
  module Dispatcher
    extend self

    # Builds an ActionMailer::MessageDelivery with HTML and text parts.
    # @api private
    def build_message(headers, &block)
      render_config_overrides = render_config(headers)
      Goodmail.with_config(render_config_overrides) do
        # Snapshot the effective config used for the eager DSL/layout render.
        # Action Mailer's MessageDelivery processes the mailer action lazily
        # and deliver_later serializes only action arguments, so the later
        # plaintext/HTML materialization must not observe a different global
        # Goodmail.config than the one that produced `raw_html_body`.
        # Sources:
        # - MessageDelivery laziness:
        #   https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/message_delivery.rb#L19-L31
        # - deliver_later serializes mailer action arguments:
        #   https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/lib/action_mailer/message_delivery.rb#L142-L155
        current_render_config = Goodmail.config.to_h

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
          layout_path: render_option(headers, :layout_path),
          unsubscribe_url: unsubscribe_url,
          preheader: preheader # Pass preheader to layout
        )

        # 6. Strip Goodmail render options and keep Action Mailer headers
        mailer_headers = slice_mail_headers(headers)

        # 7. Build the mail object via the internal Mailer class action.
        #    Attachments collected via the `attach` / `inline_image` DSL helpers
        #    flow through here so the Mailer can register them with Action
        #    Mailer's attachments hash before the `mail()` call.
        #
        #    The `preheader` is forwarded so `Goodmail::Plaintext` can strip
        #    the inbox-preview text from the plaintext part if it leaks
        #    through Premailer's extractor (which doesn't honor the hidden
        #    span's `display: none`).
        Goodmail::Mailer.compose_message(
          mailer_headers,
          raw_html_body,
          unsubscribe_url,
          builder.attachments,
          preheader: preheader,
          render_config: current_render_config
        )
      end
    end

    private

    # Pass Action Mailer's normal header surface through, excluding only
    # Goodmail render-only options such as :unsubscribe_url and :preheader.
    def slice_mail_headers(h)
      Goodmail.action_mailer_headers(h)
    end

    def render_config(headers)
      render_option(headers, :config) || render_option(headers, :configuration)
    end

    def render_option(headers, key)
      return headers[key] if headers.key?(key)

      headers[key.to_s] if headers.key?(key.to_s)
    end

    # Removed generate_plaintext - now handled by Premailer in Mailer#compose_message
  end
end
