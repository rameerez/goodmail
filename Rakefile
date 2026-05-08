# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false # Silence noisy stdlib warnings (e.g. ostruct
                    # deprecation notice in Ruby 3.4) so the run
                    # output stays focused on real test failures.
end

task default: :test
