# frozen_string_literal: true

module Goodmail
  # Base error class for Goodmail specific exceptions.
  # This allows users to rescue Goodmail::Error specifically.
  class Error < StandardError; end
end
