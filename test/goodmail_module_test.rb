# frozen_string_literal: true

require "test_helper"

# Tests for the top-level `Goodmail` module surface — the very small but
# important public seam users wire into via `gem "goodmail"`. We cover:
#
#   - Version constant exposure
#   - `Goodmail.compose` / `Goodmail.render` are public and routed
#   - `Configuration` module is mixed in via `extend`
#   - Loading the gem doesn't side-effect on requirers
class GoodmailModuleTest < Minitest::Test
  def test_VERSION_is_a_semver_string
    assert_kind_of String, Goodmail::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, Goodmail::VERSION,
                 "version should be plain semver — no pre-release suffixes shipped on master")
  end

  def test_compose_is_a_module_method
    # Locked surface: callers reach `Goodmail.compose`, not
    # `Goodmail::Dispatcher.build_message` (the latter is `@api private`).
    assert_respond_to Goodmail, :compose
    refute_includes Goodmail.singleton_methods, :build_message
  end

  def test_render_is_a_module_method
    assert_respond_to Goodmail, :render
  end

  def test_config_configure_reset_config_are_module_methods_via_extend
    # `Goodmail extend Configuration` makes these reachable on the
    # module itself (not as instance methods).
    assert_respond_to Goodmail, :config
    assert_respond_to Goodmail, :configure
    assert_respond_to Goodmail, :reset_config!
    assert_respond_to Goodmail, :configuration
  end

  def test_Configuration_module_is_present_in_the_singleton_class_ancestry
    # If a future refactor swaps `extend` for plain class methods we want
    # this test to fire — the `extend Configuration` shape is what every
    # downstream test/integration relies on.
    assert_includes Goodmail.singleton_class.ancestors, Goodmail::Configuration
  end

  def test_Builder_Layout_Email_Dispatcher_Mailer_Error_constants_are_loaded
    # Locking the surface: every component the README references is
    # reachable from the Goodmail namespace at require-time. If a
    # contributor accidentally forgets a `require_relative` in
    # `lib/goodmail.rb`, this catches it.
    assert defined?(Goodmail::Builder)
    assert defined?(Goodmail::Layout)
    assert defined?(Goodmail::EmailParts)
    assert defined?(Goodmail::Dispatcher)
    assert defined?(Goodmail::Mailer)
    assert defined?(Goodmail::Error)
    assert defined?(Goodmail::Configuration)
  end

  def test_compose_delegates_to_Dispatcher_build_message
    # The compose method is a one-liner — verify it actually calls into
    # the dispatcher (so a future refactor can't quietly stop using the
    # documented orchestration layer). We use a minitest mock with a
    # pass-through stub so the real wiring still produces a deliverable
    # message.
    captured = nil
    original = Goodmail::Dispatcher.method(:build_message)
    Goodmail::Dispatcher.define_singleton_method(:build_message) do |headers, &block|
      captured = headers
      original.call(headers, &block)
    end

    Goodmail.compose(to: "u@x.co", from: "n@x.co", subject: "Probe") { text "hi" }
    assert_equal "u@x.co", captured[:to]
    assert_equal "Probe", captured[:subject]
  ensure
    Goodmail::Dispatcher.define_singleton_method(:build_message, original) if original
  end

  def test_Goodmail_Mailer_inherits_from_ActionMailer_Base_without_modifying_it
    # The internal Mailer is a private detail. It SHOULD inherit from
    # `ActionMailer::Base` (so it picks up host-app delivery config like
    # `:smtp` settings) but MUST NOT decorate the parent class with a
    # `default from:` or anything else that would leak into other
    # mailers in the host app.
    assert_operator Goodmail::Mailer, :<, ActionMailer::Base

    # `default` returns a Hash of mailer-level defaults. Goodmail::Mailer
    # MUST NOT carry a baked-in `from:` / `cc:` / etc — those have to
    # come from the per-call `Goodmail.compose(...)` headers so callers
    # can drive identity per email.
    refute Goodmail::Mailer.default.key?(:from), "the internal Mailer must not preset a `from` address"
    refute Goodmail::Mailer.default.key?(:to),   "the internal Mailer must not preset a `to` address"
  end
end
