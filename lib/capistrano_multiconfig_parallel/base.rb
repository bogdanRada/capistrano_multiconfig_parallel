require 'rubygems'
require 'bundler'
require 'bundler/setup'
require 'inquirer'
require_relative './version'
require_relative './configuration'
# base module that has the statis methods that this gem is using
module CapistranoMulticonfigParallel
  include CapistranoMulticonfigParallel::Configuration

  ENV_KEY_JOB_ID = 'multi_cap_job_id'
  MULTI_KEY = 'multi'
  SINGLE_KEY = 'single'

  CUSTOM_COMMANDS = {
    CapistranoMulticonfigParallel::MULTI_KEY => {
      menu: 'show_menu',
      stages: 'deploy_multi_stages'
    },
    CapistranoMulticonfigParallel::SINGLE_KEY => {
      stages: 'deploy_multi_stages'
    }
  }

  class << self
    attr_accessor :show_task_progress, :interactive_menu, :execute_in_sequence, :logger, :show_task_progress_tree

    def root
      File.expand_path(File.dirname(__dir__))
    end

    def ask_confirm(message, default)
      Ask.input message, default: default
    end

    def verify_app_dependencies(stages)
      applications = stages.map { |stage| stage.split(':').reverse[1] }
      wrong = CapistranoMulticonfigParallel.configuration.application_dependencies.find do |hash|
        !applications.include?(hash[:app]) || (hash[:dependencies].present? && hash[:dependencies].find { |val| !applications.include?(val) })
      end
      raise ArgumentError, "invalid configuration for #{wrong.inspect}" if wrong.present?
    end

    def log_directory
      File.join(CapistranoMulticonfigParallel.detect_root.to_s, 'log')
    end

    def main_log_file
      File.join(log_directory, 'multi_cap.log')
    end

    def websokect_log_file
      File.join(log_directory, 'multi_cap_websocket.log')
    end

    def enable_logging
      CapistranoMulticonfigParallel.configuration_valid?
      return unless CapistranoMulticonfigParallel::CelluloidManager.debug_enabled
      FileUtils.mkdir_p(log_directory)
      log_file = File.open(main_log_file, 'w')
      log_file.sync = true
      self.logger = ::Logger.new(main_log_file)
      Celluloid.logger = logger
    end

    def log_message(message)
      return unless logger.present?
      error_message = message.respond_to?(:message) ? message.message : message.inspect
      err_backtrace = message.respond_to?(:backtrace) ? message.backtrace.join("\n\n") : ''
      if err_backtrace.present?
        logger.debug(
          class_name: message.class,
          message: error_message,
          backtrace: err_backtrace
        )
      else
        logger.debug(message)
      end
    end

    def detect_root
      if ENV['MULTI_CAP_ROOT']
        Pathname.new(ENV['MULTI_CAP_ROOT'])
      elsif defined?(::Rails)
        ::Rails.root
      else
        try_detect_capfile
      end
    end
    
    def try_detect_capfile
      root = Pathname.new(FileUtils.pwd)
      root = root.parent unless root.directory?
      root = root.parent until root.children.find{|f| f.file? &&  f.basename.to_s.downcase == "capfile"}.present? || root.root?
      raise "Can't detect Rails application root" if root.root?
      root
    end
  end
end
