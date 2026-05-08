# frozen_string_literal: true

# SimpleCov configuration file (auto-loaded before test suite)
# This keeps test_helper.rb clean and follows best practices

SimpleCov.start do
  # Use SimpleFormatter for terminal-only output (no HTML generation)
  formatter SimpleCov::Formatter::SimpleFormatter

  # Track coverage for the lib directory (gem source code)
  add_filter "/test/"

  # `lib/goodmail/version.rb` is loaded by Bundler (via the gemspec
  # `require_relative "lib/goodmail/version"`) BEFORE SimpleCov starts,
  # so its lines never get instrumented even though they're executed.
  # Excluding it keeps the report honest. Goodmail::VERSION's shape is
  # asserted in `test/goodmail_module_test.rb` instead.
  add_filter "/lib/goodmail/version.rb"

  # Track Ruby files in lib directory
  track_files "lib/**/*.rb"

  # Enable branch coverage for more detailed metrics
  enable_coverage :branch

  # Set minimum coverage threshold to prevent coverage regression.
  # Goodmail currently sits at 100% line / 100% branch — the floor is
  # set generously to allow for non-trivial future additions without
  # immediately tripping CI.
  minimum_coverage line: 90, branch: 80

  # Disambiguate parallel test runs
  command_name "Job #{ENV['TEST_ENV_NUMBER']}" if ENV["TEST_ENV_NUMBER"]
end

# Print coverage summary to terminal after tests complete
SimpleCov.at_exit do
  SimpleCov.result.format!
  puts "\n" + "=" * 60
  puts "COVERAGE SUMMARY"
  puts "=" * 60
  puts "Line Coverage:   #{SimpleCov.result.covered_percent.round(2)}%"
  branch_coverage = SimpleCov.result.coverage_statistics[:branch]&.percent&.round(2) || "N/A"
  puts "Branch Coverage: #{branch_coverage}%"
  puts "=" * 60
end
