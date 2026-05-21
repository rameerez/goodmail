# frozen_string_literal: true
require "action_mailer"

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
    # @api internal
    def compose_message(
      headers,
      html_body,
      text_body,
      unsubscribe_url,
      dsl_attachments = []
    )
      headers = headers.dup
      goodmail_add_list_unsubscribe_headers!(headers, unsubscribe_url)
      goodmail_apply_attachments!(dsl_attachments)

      # Attachments must be registered before `mail` materializes the message;
      # the block form below lets Rails build the multipart/alternative tree.
      # Sources:
      # - late attachments raise:
      #   https://github.com/rails/rails/blob/debbd18c562df17d01944c475e9291d927910b58/actionmailer/lib/action_mailer/base.rb#L766-L781
      # - block-form `mail` with direct plain/html rendering:
      #   https://github.com/rails/rails/blob/debbd18c562df17d01944c475e9291d927910b58/actionmailer/lib/action_mailer/base.rb#L851-L873
      mail(headers) do |format|
        format.text { render plain: text_body.to_s }
        format.html { render html: html_body.to_s.html_safe }
      end
    end
  end
end
