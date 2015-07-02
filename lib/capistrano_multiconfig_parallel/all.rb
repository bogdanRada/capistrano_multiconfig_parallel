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
require 'devnull'
require 'inquirer'
# fix error with not files that can not be found
Gem.find_files('composable_state_machine/**/*.rb').each { |path| require path }

Gem.find_files('capistrano_multiconfig_parallel/initializers/**/*.rb').each { |path| require path }
Gem.find_files('capistrano_multiconfig_parallel/helpers/**/*.rb').each { |path| require path }
Gem.find_files('capistrano_multiconfig_parallel/celluloid/**/*.rb').each { |path| require path }

require_relative './version'
require_relative './configuration'
require_relative './base'
require_relative './application'
