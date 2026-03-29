# frozen_string_literal: true

require "bundler/setup"
require "simplecov"
SimpleCov.start do
  add_filter "/test/"
end

require "minitest/autorun"
require "minitest/reporters"
Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)

require "tmpdir"

require "action_mailer"
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.view_paths = []

# Ensure ActiveSupport core extensions like present?/blank?/html_safe are available
require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/output_safety"

# Load the gem
require "goodmail"

# Standardize default configuration per test run
Goodmail.reset_config!
Goodmail.configure do |config|
  # Use explicit values to avoid relying on defaults in tests
  config.company_name = "Acme Inc."
  config.brand_color = "#123456"
  config.logo_url = nil
  config.company_url = nil
  config.unsubscribe_url = nil
  config.default_preheader = nil
  config.footer_text = nil
  config.show_footer_unsubscribe_link = false
  config.footer_unsubscribe_link_text = "Unsubscribe"
end