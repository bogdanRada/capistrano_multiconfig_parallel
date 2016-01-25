require 'bundler/setup'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'coveralls/rake/task'
require 'yard'
Coveralls::RakeTask.new

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.rspec_opts = ['--backtrace '] if ENV['DEBUG']
end

# desc "Prepare dummy application"
# task :prepare do
#  ENV["RAILS_ENV"] ||= 'test'
#  require File.expand_path("./spec/dummy/config/environment", File.dirname(__FILE__))
#  Dummy::Application.load_tasks
#  Rake::Task["db:test:prepare"].invoke
# end
YARD::Config.options[:load_plugins] = true
YARD::Config.load_plugins

YARD::Rake::YardocTask.new do |t|
  t.files = ['lib/**/*.rb', 'spec/**/*_spec.rb'] # optional
  t.options = ['--any', '--extra', '--opts', '--markup-provider=redcarpet', '--markup=markdown', '--debug'] # optional
  t.stats_options = ['--list-undoc'] # optional
end

desc 'Default: run the unit tests.'
task default: [:all]

desc 'Test the plugin under all supported Rails versions.'
task :all do |_t|
  if ENV['TRAVIS']
    exec('bundle exec rake  spec && bundle exec rake coveralls:push')
  else
    exec('bundle exec rake spec')
  end
end

task :docs do
  exec('bundle exec inch --pedantic && bundle exec yard --list-undoc')
end
