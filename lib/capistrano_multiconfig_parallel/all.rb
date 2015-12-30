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
require 'rack'

require 'logger'
require 'fileutils'
require 'pp'
require 'yaml'
require 'stringio'
require 'io/console'

# capistrano requirements
require 'rake'
require 'capistrano/all'

# fix error with not files that can not be found
Gem.find_files('composable_state_machine/**/*.rb').each { |path| require path }

%w(classes helpers celluloid initializers).each do |folder_name|
  Gem.find_files("capistrano_multiconfig_parallel/#{folder_name}/**/*.rb").each { |path| require path }
end

require_relative './version'
require_relative './base'
