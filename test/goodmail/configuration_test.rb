# frozen_string_literal: true
require_relative "../test_helper"

class GoodmailConfigurationTest < Minitest::Test
  def setup
    Goodmail.reset_config!
  end

  def test_defaults_are_duplicated_and_mutable_copy
    c1 = Goodmail.config
    c2 = Goodmail.config
    refute_same c1, Goodmail::Configuration::DEFAULT_CONFIG
    refute_same c2, Goodmail::Configuration::DEFAULT_CONFIG
    # Mutate current config and ensure DEFAULT_CONFIG remains unchanged
    original_default_brand = Goodmail::Configuration::DEFAULT_CONFIG.brand_color
    c1.brand_color = "#abcdef"
    assert_equal "#abcdef", c1.brand_color
    assert_equal original_default_brand, Goodmail::Configuration::DEFAULT_CONFIG.brand_color
  end

  def test_configure_requires_company_name
    Goodmail.reset_config!
    assert_raises(Goodmail::Error) do
      Goodmail.configure do |c|
        c.company_name = "  "
      end
    end
  end

  def test_configure_validates_and_persists
    Goodmail.reset_config!
    Goodmail.configure do |c|
      c.company_name = "Zeta LLC"
      c.brand_color = "#abcdef"
      c.footer_text = "Why you got this"
      c.show_footer_unsubscribe_link = true
      c.footer_unsubscribe_link_text = "Manage"
    end
    c = Goodmail.config
    assert_equal "Zeta LLC", c.company_name
    assert_equal "#abcdef", c.brand_color
    assert_equal "Why you got this", c.footer_text
    assert_equal true, c.show_footer_unsubscribe_link
    assert_equal "Manage", c.footer_unsubscribe_link_text
  end

  def test_reset_config_resets_to_defaults
    Goodmail.configure { |c| c.company_name = "A" }
    Goodmail.reset_config!
    Goodmail.configure { |c| c.company_name = "Acme Inc." }
    assert_equal "Acme Inc.", Goodmail.config.company_name
  end
end