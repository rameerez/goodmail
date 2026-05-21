# frozen_string_literal: true

require "test_helper"

# Exhaustive tests for `Goodmail::Configuration`. The module is mixed into
# the top-level `Goodmail` namespace via `extend Configuration` in
# `lib/goodmail.rb`, so the public surface is reached as `Goodmail.config`,
# `Goodmail.configure { ... }`, `Goodmail.reset_config!`, and the
# `:configuration` alias.
class ConfigurationTest < Minitest::Test
  def setup
    # Skip the parent setup that pre-configures with defaults — every test
    # in this file wants to start from a fully fresh, unconfigured state.
    Goodmail.reset_config!
    ActionMailer::Base.deliveries.clear
  end

  def test_config_returns_a_dup_of_DEFAULT_CONFIG_when_unconfigured
    cfg = Goodmail.config
    assert_kind_of OpenStruct, cfg
    assert_equal "Example Inc.", cfg.company_name
    assert_equal "#348eda", cfg.brand_color
    assert_nil cfg.logo_url
    assert_nil cfg.company_url
    assert_nil cfg.unsubscribe_url
    assert_nil cfg.default_preheader
    assert_nil cfg.footer_text
    assert_equal false, cfg.show_footer_unsubscribe_link
    assert_equal "Unsubscribe", cfg.footer_unsubscribe_link_text
  end

  def test_DEFAULT_CONFIG_constant_is_frozen_and_cannot_be_mutated
    # Defending against accidental mutation: if a future contributor pulls
    # the constant directly (instead of calling `Goodmail.config`), they
    # cannot poison defaults for every other consumer in the same process.
    assert_predicate Goodmail::Configuration::DEFAULT_CONFIG, :frozen?
    assert_raises(FrozenError) do
      Goodmail::Configuration::DEFAULT_CONFIG.company_name = "Mutant Co."
    end
  end

  def test_config_is_memoized_after_first_access
    a = Goodmail.config
    b = Goodmail.config
    assert_same a, b, "config should return the same instance on repeat reads"
  end

  def test_each_call_to_config_after_reset_returns_a_fresh_dup
    a = Goodmail.config
    a.brand_color = "#ff0000"
    Goodmail.reset_config!
    b = Goodmail.config
    refute_same a, b
    assert_equal "#348eda", b.brand_color, "fresh dup should not see the previous instance's mutations"
  end

  def test_configuration_is_an_alias_of_config
    assert_same Goodmail.config, Goodmail.configuration
  end

  def test_with_config_applies_a_temporary_thread_local_override
    Goodmail.configure { |c| c.company_name = "Global Co." }

    Goodmail.with_config(company_name: "Tenant Co.", brand_color: "#123456") do
      assert_equal "Tenant Co.", Goodmail.config.company_name
      assert_equal "#123456", Goodmail.config.brand_color
    end

    assert_equal "Global Co.", Goodmail.config.company_name
    assert_equal "#348eda", Goodmail.config.brand_color
  end

  def test_with_config_validates_required_keys_without_mutating_global_config
    Goodmail.configure { |c| c.company_name = "Global Co." }

    error = assert_raises(Goodmail::Error) do
      Goodmail.with_config(company_name: " ") { flunk "invalid config should not yield" }
    end

    assert_match(/company_name/, error.message)
    assert_equal "Global Co.", Goodmail.config.company_name
  end

  def test_with_config_accepts_each_pair_configuration_objects
    each_pair_config_class = Class.new do
      def initialize(pairs)
        @pairs = pairs
      end

      def each_pair(&block)
        @pairs.each(&block)
      end
    end
    each_pair_config = each_pair_config_class.new([[:company_name, "Each Pair Co."]])

    Goodmail.with_config(each_pair_config) do
      assert_equal "Each Pair Co.", Goodmail.config.company_name
    end
  end

  def test_configure_mutates_global_config_even_inside_a_temporary_override
    Goodmail.configure { |c| c.company_name = "Global Co." }

    Goodmail.with_config(company_name: "Tenant Co.") do
      Goodmail.configure { |c| c.company_name = "Updated Global Co." }
      assert_equal "Tenant Co.", Goodmail.config.company_name
    end

    assert_equal "Updated Global Co.", Goodmail.config.company_name
  end

  def test_configure_yields_the_config_object
    yielded = nil
    Goodmail.configure do |c|
      yielded = c
      c.company_name = "Yield Co."
    end
    assert_same Goodmail.config, yielded
  end

  def test_configure_persists_overrides
    Goodmail.configure do |c|
      c.company_name = "Override Co."
      c.brand_color = "#000000"
      c.logo_url = "https://cdn.example.com/logo.png"
      c.company_url = "https://example.com"
      c.unsubscribe_url = "https://example.com/unsubscribe"
      c.default_preheader = "Hi from Override Co."
      c.footer_text = "Why you got this email"
      c.show_footer_unsubscribe_link = true
      c.footer_unsubscribe_link_text = "Unsuscríbete"
    end

    cfg = Goodmail.config
    assert_equal "Override Co.", cfg.company_name
    assert_equal "#000000", cfg.brand_color
    assert_equal "https://cdn.example.com/logo.png", cfg.logo_url
    assert_equal "https://example.com", cfg.company_url
    assert_equal "https://example.com/unsubscribe", cfg.unsubscribe_url
    assert_equal "Hi from Override Co.", cfg.default_preheader
    assert_equal "Why you got this email", cfg.footer_text
    assert_equal true, cfg.show_footer_unsubscribe_link
    assert_equal "Unsuscríbete", cfg.footer_unsubscribe_link_text
  end

  def test_configure_validates_after_yield_so_user_error_surfaces_immediately
    error = assert_raises(Goodmail::Error) do
      Goodmail.configure do |c|
        c.company_name = nil
      end
    end
    assert_match(/Missing required Goodmail configuration keys.*company_name/, error.message)
  end

  def test_configure_treats_blank_string_company_name_as_missing
    error = assert_raises(Goodmail::Error) do
      Goodmail.configure do |c|
        c.company_name = "   "
      end
    end
    assert_match(/company_name/, error.message)
  end

  def test_configure_treats_empty_string_company_name_as_missing
    error = assert_raises(Goodmail::Error) do
      Goodmail.configure do |c|
        c.company_name = ""
      end
    end
    assert_match(/company_name/, error.message)
  end

  def test_validation_error_message_directs_user_to_initializer
    error = assert_raises(Goodmail::Error) do
      Goodmail.configure do |c|
        c.company_name = nil
      end
    end
    assert_match(%r{config/initializers/goodmail\.rb}, error.message)
  end

  def test_required_keys_constant_lists_company_name_only_for_now
    # If a contributor adds another required key they must update both this
    # test and the validation error string. Locking the surface keeps the
    # gem's contract explicit.
    assert_equal %i[company_name], Goodmail::Configuration::REQUIRED_CONFIG_KEYS
  end

  def test_reset_config_back_to_unconfigured_state
    Goodmail.configure do |c|
      c.company_name = "Will Be Reset"
      c.brand_color = "#ff0000"
    end
    Goodmail.reset_config!

    # Default brand color is restored AND a re-read uses a fresh dup of the
    # frozen default, not the previous instance.
    assert_equal "#348eda", Goodmail.config.brand_color
    assert_equal "Example Inc.", Goodmail.config.company_name
  end

  def test_validate_config_raises_a_Goodmail_Error_subclass_of_StandardError
    error = assert_raises(Goodmail::Error) do
      Goodmail.configure do |c|
        c.company_name = nil
      end
    end
    assert_kind_of StandardError, error
  end
end
