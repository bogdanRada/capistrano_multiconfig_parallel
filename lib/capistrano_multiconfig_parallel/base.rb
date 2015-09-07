# base module that has the statis methods that this gem is using
module CapistranoMulticonfigParallel
  include CapistranoMulticonfigParallel::Configuration

  ENV_KEY_JOB_ID = 'multi_cap_job_id'
  MULTI_KEY = 'multi'
  SINGLE_KEY = 'single'
  GITFLOW_TAG_STAGING_TASK = 'gitflow:tag_staging'
  GITFLOW_CALCULATE_TAG_TASK = 'gitflow:calculate_tag'
  GITFLOW_VERIFY_UPTODATE_TASK = 'gitflow:verify_up_to_date'

  CUSTOM_COMMANDS = {
    CapistranoMulticonfigParallel::MULTI_KEY => {
      stages: 'deploy_multi_stages'
    },
    CapistranoMulticonfigParallel::SINGLE_KEY => {
      stages: 'deploy_multi_stages'
    }
  }

  class << self
    attr_accessor :execute_in_sequence, :logger, :original_args, :interactive_menu

    def root
      File.expand_path(File.dirname(__dir__))
    end

    def check_terminal_tty
      $stdin.sync = true if $stdin.isatty
      $stdout.sync = true if $stdout.isatty
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
      FileUtils.mkdir_p(log_directory) unless File.directory?(log_directory)
      if CapistranoMulticonfigParallel::CelluloidManager.debug_enabled.to_s.downcase == 'true'
        FileUtils.touch(main_log_file) unless File.file?(main_log_file)
        if ENV[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
          log_file = File.open(main_log_file, 'w')
          log_file.sync = true
        end
        self.logger = ::Logger.new(main_log_file)
      else
        self.logger = ::Logger.new(DevNull.new)
      end
      Celluloid.logger = CapistranoMulticonfigParallel.logger
      Celluloid.task_class = Celluloid::TaskThread
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
      root = root.parent until root.children.find { |f| f.file? && f.basename.to_s.downcase == 'capfile' }.present? || root.root?
      raise "Can't detect Rails application root" if root.root?
      root
    end
  end
end
