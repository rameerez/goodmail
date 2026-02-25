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
      # Optional: URL the header logo links to.
      company_url:  nil,
      # Optional: Global default unsubscribe URL.
      unsubscribe_url: nil,
      # Optional: Default preheader text (appears after subject in inbox preview).
      default_preheader: nil,
      # Optional footer text (e.g., "Why you received this email")
      footer_text:  nil,
      # Show a visible unsubscribe link in the footer?
      show_footer_unsubscribe_link: false,
      # Text for the footer unsubscribe link
      footer_unsubscribe_link_text: "Unsubscribe"
    ).freeze # Freeze the default object to prevent accidental modification

    # Define required keys that MUST be set by the user (cannot be nil/empty)
    REQUIRED_CONFIG_KEYS = %i[company_name].freeze

    # Provides the configuration block helper.
    # Ensures validation runs after the block is executed.
    def configure
      yield config # Ensures config is initialized via accessor
      validate_config!(config)
    end

    # Returns the current configuration object.
    # Initializes with a copy of the defaults if not already configured.
    def config
      @config = DEFAULT_CONFIG.dup unless defined?(@config) && @config
      @config
    end
    alias_method :configuration, :config

    # Resets the configuration back to the default values.
    # Primarily useful for testing environments.
    def reset_config!
      @config = nil
    end

    private

    # Validates that required configuration keys are set.
    # Raises Goodmail::Error if any required keys are missing or blank.
    def validate_config!(current_config)
      missing_keys = REQUIRED_CONFIG_KEYS.select do |key|
        value = current_config[key]
        value.nil? || (value.respond_to?(:strip) && value.strip.empty?)
      end

      unless missing_keys.empty?
        raise Goodmail::Error, "Missing required Goodmail configuration keys: #{missing_keys.join(', ')}. Please set them in config/initializers/goodmail.rb"
      end

      # Optional: Add validation for URL formats if needed
    end
  end
end
