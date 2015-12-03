module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module CoreHelper
    extend ActiveSupport::Concern
    included do
      def config_file
        File.join(detect_root.to_s, 'config', 'multi_cap.yml')
      end

      def internal_config_directory
        File.join(root.to_s, 'capistrano_multiconfig_parallel', 'configuration')
      end

      def find_env_multi_cap_root
        ENV['MULTI_CAP_ROOT']
      end

      def detect_root
        if find_env_multi_cap_root
          Pathname.new(find_env_multi_cap_root)
        elsif defined?(::Rails)
          ::Rails.root
        else
          try_detect_capfile
        end
      end

      def log_directory
        File.join(detect_root.to_s, 'log')
      end

      def main_log_file
        File.join(log_directory, 'multi_cap.log')
      end

      def websokect_log_file
        File.join(log_directory, 'multi_cap_websocket.log')
      end

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

      def log_message(message)
        return unless logger.present?
        logger.debug(
          class_name: message.class,
          message: message.respond_to?(:message) ? message.message : message.inspect,
          backtrace: message.respond_to?(:backtrace) ? message.backtrace.join("\n\n") : ''
        )
      end

      def try_detect_capfile
        root = Pathname.new(FileUtils.pwd)
        root = root.parent unless root.directory?
        root = root.parent until root.children.find { |f| f.file? && f.basename.to_s.downcase == 'capfile' }.present? || root.root?
        fail "Can't detect Capfile in the  application root".red if root.root?
        root
      end

      def find_loaded_gem(name)
        Gem.loaded_specs.values.find { |repo| repo.name == name }
      end
    end
  end
end
