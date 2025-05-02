# frozen_string_literal: true
require "ostruct"

module Goodmail
  # Handles configuration settings for the Goodmail gem.
  module Configuration
    # Default configuration values
    DEFAULT_CONFIG = OpenStruct.new(
      brand_color:  "#348eda",
      company_name: "Example Inc.",
      logo_url:     nil,
      # Optional footer text (e.g., "Why you received this email")
      footer_text:  nil,
      # Optional: Global default unsubscribe URL.
      # Can be overridden per email via headers[:unsubscribe_url].
      # User is responsible for providing a valid URL to manage email subscriptions.
      unsubscribe_url: nil,
      # Show a visible unsubscribe link in the footer?
      show_footer_unsubscribe_link: false,
      # Text for the footer unsubscribe link
      footer_unsubscribe_link_text: "Unsubscribe"
    ).freeze # Freeze the default object to prevent accidental modification

    # Provides the configuration block helper.
    # Allows users to modify the configuration in an initializer:
    #   Goodmail.configure do |config|
    #     config.brand_color = "#ff0000"
    #   end
    def configure
      # Ensure config is initialized before yielding
      yield config
    end

    # Returns the current configuration object.
    # Initializes with a copy of the defaults if not already configured.
    def config
      # Use defined? check for more robust initialization in edge cases
      @config = DEFAULT_CONFIG.dup unless defined?(@config) && @config
      @config
    end

    # Resets the configuration back to the default values.
    # Primarily useful for testing environments.
    def reset_config!
      @config = nil
    end

    # Removed attr_reader/writer - relying on explicit config method.
  end
end
