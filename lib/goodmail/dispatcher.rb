# frozen_string_literal: true
require "action_mailer"
require_relative "mailer"

module Goodmail
  # Responsible for orchestrating the building of the Action Mailer delivery.
  module Dispatcher
    extend self

    # Builds an ActionMailer::MessageDelivery with HTML and text parts.
    # @api private
    def build_message(headers, &block)
      headers = headers.dup
      render_config_overrides = render_config(headers)

      Goodmail.with_config(render_config_overrides) do
        parts = Goodmail.render(headers, &block)

        # ActionMailer::MessageDelivery processes this mailer action lazily and
        # `deliver_later` serializes only action arguments, so pass already
        # rendered strings and plain attachment descriptor hashes into the action.
        # Sources:
        # - MessageDelivery laziness:
        #   https://github.com/rails/rails/blob/debbd18c562df17d01944c475e9291d927910b58/actionmailer/lib/action_mailer/message_delivery.rb#L22-L35
        # - deliver_later serializes mailer action arguments:
        #   https://github.com/rails/rails/blob/debbd18c562df17d01944c475e9291d927910b58/actionmailer/lib/action_mailer/message_delivery.rb#L142-L155
        Goodmail::Mailer.compose_message(
          slice_mail_headers(headers),
          parts.html,
          parts.text,
          resolved_unsubscribe_url(headers),
          parts.attachments
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

    def resolved_unsubscribe_url(headers)
      render_option(headers, :unsubscribe_url) || Goodmail.config.unsubscribe_url
    end

    def render_option(headers, key)
      return headers[key] if headers.key?(key)

      headers[key.to_s] if headers.key?(key.to_s)
    end
  end
end
