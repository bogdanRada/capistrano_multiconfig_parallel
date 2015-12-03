require_relative './core_helper'
module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module ApplicationHelper
    include CapistranoMulticonfigParallel::CoreHelper

  module_function

    def app_debug_enabled?
      app_configuration.multi_debug.to_s.downcase == 'true'
    end

    def celluloid_log(_message, worker_log = nil)
      worker_log.present? ? worker_log : Celluloid.logger
      worker_log.debug("worker #{@job_id} received #{job.inspect}") if worker_log.present? && app_debug_enabled?
    end

    def show_warning(message)
      warn message if app_debug_enabled?
    end

    def app_configuration
      CapistranoMulticonfigParallel.configuration
    end

    def app_logger
      CapistranoMulticonfigParallel.logger
    end

    def check_terminal_tty
      $stdin.sync = true if $stdin.isatty
      $stdout.sync = true if $stdout.isatty
    end

    def find_loaded_gem(name)
      Gem.loaded_specs.values.find { |repo| repo.name == name }
    end

    def ask_confirm(message, default)
      `stty -raw echo`
      check_terminal_tty
      result = Ask.input message, default: default
      $stdout.flush
      `stty -raw echo`
      return result
    rescue
      return nil
    end

    def log_message(message)
      return unless app_logger.present?
      app_logger.debug(
        class_name: message.class,
        message: message.respond_to?(:message) ? message.message : message.inspect,
        backtrace: message.respond_to?(:backtrace) ? message.backtrace.join("\n\n") : ''
      )
    end

    def change_config_type(type)
      ['boolean'].include?(type) ? type.delete(':').to_sym : type.constantize
    end

    def strip_characters_from_string(value)
      return unless value.present?
      value = value.delete("\r\n").delete("\n")
      value = value.gsub(/\s+/, ' ').strip if value.present?
      value
    end

    def parse_task_string(string) # :nodoc:
      /^([^\[]+)(?:\[(.*)\])$/ =~ string.to_s

      name           = Regexp.last_match(1)
      remaining_args = Regexp.last_match(2)

      return string, [] unless name
      return name,   [] if     remaining_args.empty?

      args = []

      loop do
        /((?:[^\\,]|\\.)*?)\s*(?:,\s*(.*))?$/ =~ remaining_args

        remaining_args = Regexp.last_match(2)
        args << Regexp.last_match(1).gsub(/\\(.)/, '\1')
        break if remaining_args.blank?
      end

      [name, args]
    end
  end
end
