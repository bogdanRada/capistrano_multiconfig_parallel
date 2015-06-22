require 'rubygems'
require 'bundler'
require 'bundler/setup'
require 'rake'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/keys'
require 'active_support/concern'
require 'celluloid/autostart'
require 'celluloid/pmap'
require 'composable_state_machine'
require 'formatador'
require 'eventmachine'
require 'right_popen'
require 'colorize'
require 'logger'
require 'terminal-table'
require 'colorize'
require 'celluloid_pubsub'
require 'capistrano/all'
require 'fileutils'
require 'logger'
require 'pp'
require 'configurations'
# fix error with not files that can not be found
Gem.find_files('composable_state_machine/**/*.rb').each { |path| require path }

Gem.find_files('capistrano_multiconfig_parallel/initializers/**/*.rb').each { |path| require path }
Gem.find_files('capistrano_multiconfig_parallel/helpers/**/*.rb').each { |path| require path }
Gem.find_files('capistrano_multiconfig_parallel/celluloid/**/*.rb').each { |path| require path }

require_relative './base'
require_relative 'application'

module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    def self.start
      if $stdin.isatty
        $stdin.sync = true
      end
      if $stdout.isatty
        $stdout.sync = true
      end
      CapistranoMulticonfigParallel.configuration_valid?
      CapistranoMulticonfigParallel.verify_app_dependencies(stages) if CapistranoMulticonfigParallel.configuration.track_dependencies
      CapistranoMulticonfigParallel::Application.new.run
    rescue Interrupt
      `stty icanon echo`
      $stderr.puts 'Command cancelled.'
    rescue => error
      $stderr.puts error
      exit(1)
    end
  end
end
