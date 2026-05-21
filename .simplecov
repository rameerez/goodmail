# frozen_string_literal: true

# SimpleCov configuration file, loaded by test/test_helper.rb when
# COVERAGE=1 is set. Normal test runs skip coverage instrumentation.

SimpleCov.start do
  # Use SimpleFormatter for terminal-only output (no HTML generation)
  formatter SimpleCov::Formatter::SimpleFormatter
  use_merging false

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
  # Goodmail currently sits at 100% line coverage; the branch floor is set
  # generously to allow non-trivial future additions without immediately
  # tripping CI.
  minimum_coverage line: 90, branch: 80

  # Disambiguate parallel test runs
  command_name "Job #{ENV['TEST_ENV_NUMBER']}" if ENV["TEST_ENV_NUMBER"]
end

# Print coverage summary to terminal after tests complete
SimpleCov.at_exit do
  SimpleCov.result.format!
  if ENV["COVERAGE_DETAIL"]
    SimpleCov.result.files.each do |file|
      missed_lines = file.missed_lines.map(&:line_number)
      next if missed_lines.empty?

      puts "#{file.filename}:#{missed_lines.join(',')}"
    end
  end
  puts "\n#{'=' * 60}"
  puts "COVERAGE SUMMARY"
  puts "=" * 60
  puts "Line Coverage:   #{SimpleCov.result.covered_percent.round(2)}%"
  branch_coverage = SimpleCov.result.coverage_statistics[:branch]&.percent&.round(2) || "N/A"
  puts "Branch Coverage: #{branch_coverage}%"
  puts "=" * 60
end
