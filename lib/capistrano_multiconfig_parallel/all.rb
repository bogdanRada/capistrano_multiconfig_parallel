require 'rubygems'
require 'bundler'
require 'bundler/setup'

require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/module/delegation'
require 'active_support/concern'

require_relative './helpers/base_actor_helper'
require 'celluloid/pmap'
require 'celluloid_pubsub'

require 'composable_state_machine'
require 'eventmachine'
require 'right_popen'
require 'colorize'
require 'terminal-table'
require 'configliere'
require 'devnull'
require 'inquirer'
require 'rack'
require 'rake'

require 'etc'
require 'logger'
require 'fileutils'
require 'pp'
require 'yaml'
require 'stringio'
require 'io/console'
require 'base64'
require 'socket'
require 'securerandom'
require 'forwardable'

# fix error with not files that can not be found
 Gem.find_files('composable_state_machine/**/*.rb').each { |path| require path }

%w(helpers classes celluloid).each do |folder_name|
  Gem.find_files("capistrano_multiconfig_parallel/#{folder_name}/**/*.rb").each { |path| require path }
end

%w(version base application).each do |filename|
  Gem.find_files("capistrano_multiconfig_parallel/#{filename}.rb").each { |path| require path }
end

%w(initializers).each do |folder_name|
  Gem.find_files("capistrano_multiconfig_parallel/#{folder_name}/**/*.rb").each { |path| require path }
end
