require 'rubygems'
require 'bundler'
require 'bundler/setup'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/keys'
require 'active_support/concern'

require 'celluloid/autostart'
require 'celluloid/pmap'

require 'composable_state_machine'
require 'eventmachine'
require 'right_popen'
require 'colorize'
require 'terminal-table'
require 'celluloid_pubsub'
require 'configliere'
require 'devnull'
require 'inquirer'

require 'logger'
require 'fileutils'
require 'pp'
require 'yaml'
require 'stringio'

# capistrano requirements
require 'rake'
require 'capistrano/all'

# fix error with not files that can not be found
Gem.find_files('composable_state_machine/**/*.rb').each { |path| require path }

Gem.find_files('capistrano_multiconfig_parallel/**/*.rb').each { |path| require path }

require_relative './version'
require_relative './base'
require_relative './application'
