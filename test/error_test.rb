# frozen_string_literal: true

require "test_helper"

# Tiny class, but its identity matters: every Goodmail-side failure
# raises `Goodmail::Error` (validation, layout-render failures, etc.)
# so callers can `rescue Goodmail::Error` once instead of dealing with
# a zoo of subclasses. This file locks that contract.
class ErrorTest < Minitest::Test
  def test_Goodmail_Error_is_a_StandardError_subclass
    assert_operator Goodmail::Error, :<, StandardError
  end

  def test_Goodmail_Error_can_be_raised_with_a_message
    error = assert_raises(Goodmail::Error) { raise Goodmail::Error, "boom" }
    assert_equal "boom", error.message
  end

  def test_Goodmail_Error_is_what_validation_raises
    Goodmail.reset_config!
    error = assert_raises(Goodmail::Error) do
      Goodmail.configure { |c| c.company_name = nil }
    end
    assert_kind_of Goodmail::Error, error
  end

  def test_Goodmail_Error_is_what_layout_raises_on_missing_template
    error = assert_raises(Goodmail::Error) do
      Goodmail::Layout.render("<p>x</p>", "Subj", layout_path: "/tmp/never-#{rand(1_000_000)}.erb")
    end
    assert_kind_of Goodmail::Error, error
  end
end
