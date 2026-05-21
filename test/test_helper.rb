# frozen_string_literal: true

# Goodmail test suite — Minitest 6+ idioms.
#
# DESIGN NOTES
#
# Goodmail is a content-pipeline gem (DSL → HTML/text → ActionMailer message),
# not a Rails engine. So the suite deliberately avoids:
#
#   - A dummy Rails app (no schema, no controllers, no fixtures needed)
#   - SQLite + Active Record (no persistence)
#   - WebMock / VCR (no network)
#
# Everything we exercise can be reached purely through the gem's public
# entry points: `Goodmail.configure`, `Goodmail.compose`, `Goodmail.render`,
# and the `Goodmail::Builder` DSL. Action Mailer's `:test` delivery method
# captures `Goodmail.compose(...).deliver_now` calls into
# `ActionMailer::Base.deliveries` so the suite can inspect the encoded
# message without sending real mail.
#
# MINITEST 6 BREAKING CHANGES THE SUITE ASSUMES
#
#   - `Minitest::Mock` was extracted to the `minitest-mock` gem in 6.0.
#     We add it as a dev/test dependency in `Gemfile` and `require` it
#     here so test files can use `Minitest::Mock` without ceremony.
#     (The suite does not actually rely on mocks today, but the require
#     is here to keep parity with future contributors who reach for it.)
#   - `assert_equal(nil, value)` is removed; use `assert_nil(value)`.
#   - `assert_send` is removed; use `assert_predicate` / `assert_operator`.
#   - `MiniTest` (PascalCase-Test) namespace is gone; only `Minitest`.
#   - Spec expectations are removed from `Object` — use the assertion
#     style throughout.
#   - Plugin loading is opt-in.
#
# Source: https://github.com/minitest/minitest/blob/master/History.rdoc
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# SimpleCov MUST be loaded BEFORE any gem code is required so the lines loaded
# during `require "goodmail"` are counted. Keep it opt-in so normal local and
# CI test runs stay fast; use `COVERAGE=1 bundle exec rake test`.
require "simplecov" if ENV["COVERAGE"]

require "minitest/autorun"
require "minitest/mock"
require "minitest/reporters"
require "minitest/pride" if ENV["PRIDE"]

# Use the standard Minitest::Reporters output for consistency with
# sibling gems' test runs. `DefaultReporter` keeps the dotted progress
# output but adds colorization and a per-test summary line on failure.
Minitest::Reporters.use!(Minitest::Reporters::DefaultReporter.new(color: true))

# Action Mailer needs to know about a default delivery method before any
# Mailer subclass loads — `Goodmail::Mailer` inherits from
# `ActionMailer::Base` and inspects ActionMailer config at boot. Setting
# `:test` here means every `Goodmail.compose(...).deliver_now` call lands
# in `ActionMailer::Base.deliveries`.
require "action_mailer"
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.raise_delivery_errors = true

# Now load the gem under test.
require "goodmail"

# Reusable defaults for tests that need a configured gem. Each test file
# that touches `Goodmail.config` resets first via `setup` (see below) so
# tests stay independent.
module GoodmailTestConfig
  DEFAULTS = {
    company_name: "Test Co.",
    brand_color: "#111827",
    logo_url: nil,
    company_url: nil,
    unsubscribe_url: nil,
    default_preheader: nil,
    footer_text: nil,
    show_footer_unsubscribe_link: false,
    footer_unsubscribe_link_text: "Unsubscribe"
  }.freeze

  def self.configure(overrides = {})
    Goodmail.reset_config!
    Goodmail.configure do |c|
      DEFAULTS.merge(overrides).each { |k, v| c[k] = v }
    end
  end
end

# Every test class inherits from `Minitest::Test`. Shared lifecycle:
#
#   1. Reset Goodmail config + apply test defaults.
#   2. Clear `ActionMailer::Base.deliveries` so each test inspects only
#      its own messages.
#
# We keep the helpers dead simple — no DSLs on top of Minitest, no
# `it`/`describe` spec blocks (Minitest 6 removed `must_*` expectations
# from Object anyway, and the assertion style is the canonical surface).
class Minitest::Test
  def setup
    super
    GoodmailTestConfig.configure
    ActionMailer::Base.deliveries.clear
  end

  # Materialize a `Goodmail.compose(...)` MessageDelivery into a real
  # `Mail::Message` and return it for inspection. Avoids the
  # boilerplate of calling `.message` everywhere.
  def materialize(delivery)
    delivery.message
  end

  # Flatten a multipart Mail::Message to its decoded HTML body. Goodmail
  # always emits multipart/alternative (text + html), so plain `.body`
  # is a stub — the actual content lives on the leaf parts.
  def html_body(msg)
    part = msg.html_part || msg.body.parts.find { |p| p.content_type.to_s.start_with?("text/html") }
    part.body.decoded
  end

  def text_body(msg)
    part = msg.text_part || msg.body.parts.find { |p| p.content_type.to_s.start_with?("text/plain") }
    part.body.decoded
  end
end
