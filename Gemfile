# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in goodmail.gemspec
gemspec

# Build & release tools
gem "rake", "~> 13.0"

group :development do
  gem "irb"

  # Code quality
  gem "rubocop", "~> 1.0"
  gem "rubocop-minitest", "~> 0.35"
  gem "rubocop-performance", "~> 1.0"
end

group :development, :test do
  # Minitest 6 split `Minitest::Mock` into the standalone gem
  # `minitest-mock`. Pin >= 6 so contributors get the same runtime +
  # matching mock surface.
  gem "minitest", "~> 6.0"
  gem "minitest-mock"
  gem "minitest-reporters"
  gem "simplecov", require: false
end
