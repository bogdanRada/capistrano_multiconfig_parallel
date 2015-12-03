module CapistranoMulticonfigParallel
  # helper methods used for the base class
  module Helper
    extend ActiveSupport::Concern

    included do
      attr_accessor :logger, :original_args

      def root
        File.expand_path(File.dirname(File.dirname(__dir__)))
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
        FileUtils.mkdir_p(log_directory) unless File.directory?(log_directory)
        if CapistranoMulticonfigParallel::CelluloidManager.debug_enabled.to_s.downcase == 'true'
          FileUtils.touch(main_log_file) unless File.file?(main_log_file)
          log_file = File.open(main_log_file, 'w')
          log_file.sync = true
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
        raise "Can't detect Capfile in the  application root".red if root.root?
        root
      end

      def find_loaded_gem(name)
        Gem.loaded_specs.values.find { |repo| repo.name == name }
      end
    end
  end
end
