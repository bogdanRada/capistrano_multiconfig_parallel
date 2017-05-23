require 'rubygems'
require 'bundler'
require 'bundler/setup'

require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/hash/reverse_merge'
require 'active_support/core_ext/array/extract_options'
require 'active_support/core_ext/enumerable'

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
require "capistrano_sentinel"
require 'powerbar'

require 'etc'
require 'logger'
require 'fileutils'
require 'pp'
require 'yaml'
require 'stringio'
require 'io/console'
require 'forwardable'
require 'English'

# fix error with not files that can not be found
 Gem.find_files('composable_state_machine/**/*.rb').each { |path| require path }

require_relative './helpers/base_actor_helper'

%w(helpers classes celluloid).each do |folder_name|
  Gem.find_files("capistrano_multiconfig_parallel/#{folder_name}/**/*.rb").each { |path| require path }
end

%w(version base application).each do |filename|
  Gem.find_files("capistrano_multiconfig_parallel/#{filename}.rb").each { |path| require path }
end

Terminal::Table::Style.defaults = {:width => 140}
