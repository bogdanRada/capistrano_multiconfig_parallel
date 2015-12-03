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
require 'eventmachine'
require 'right_popen'
require 'colorize'
require 'logger'
require 'terminal-table'

require 'celluloid_pubsub'
require 'capistrano/all'
require 'fileutils'

require 'configliere'
require 'pp'
require 'devnull'
require 'inquirer'
require 'yaml'
require 'stringio'
# fix error with not files that can not be found
Gem.find_files('composable_state_machine/**/*.rb').each { |path| require path }

Gem.find_files('capistrano_multiconfig_parallel/classes/**/*.rb').each { |path| require path }
Gem.find_files('capistrano_multiconfig_parallel/helpers/**/*.rb').each { |path| require path }
Gem.find_files('capistrano_multiconfig_parallel/celluloid/**/*.rb').each { |path| require path }

require_relative './version'
require_relative './base'
require_relative './application'
