module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module CoreHelper
  module_function

    def internal_config_directory
      File.join(root.to_s, 'capistrano_multiconfig_parallel', 'configuration')
    end

    def internal_config_file
      File.join(internal_config_directory, 'default.yml')
    end

    def default_internal_config
      @default_config ||= YAML.load_file(internal_config_file)['default_config']
      @default_config
    end

    def find_env_multi_cap_root
      ENV['MULTI_CAP_ROOT']
    end

    def root
      File.expand_path(File.dirname(File.dirname(__dir__)))
    end

    def find_config_type(type)
      ['boolean'].include?(type.to_s) ? type.to_s.delete(':').to_sym : type.to_s.constantize
    end

    def try_detect_capfile
      root = Pathname.new(FileUtils.pwd)
      root = root.parent unless root.directory?
      root = root.parent until root.children.find { |f| f.file? && f.basename.to_s.downcase == 'capfile' }.present? || root.root?
      fail "Can't detect Capfile in the  application root".red if root.root?
      root
    end

    def app_debug_enabled?
      app_configuration.multi_debug.to_s.downcase == 'true'
    end

    def show_warning(message)
      warn message if app_debug_enabled?
    end

    def app_configuration
      CapistranoMulticonfigParallel.configuration
    end

    def custom_commands
      CapistranoMulticonfigParallel.custom_commands
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

    def log_error(message)
      log_to_file(
        class_name: message.class,
        message: message.respond_to?(:message) ? message.message : message.inspect,
        backtrace: message.respond_to?(:backtrace) ? message.backtrace.join("\n\n") : ''
      )
    end

    def log_to_file(message, job_id = nil)
      worker_log = job_id.present? ? find_worker_log(job_id) : app_logger
      worker_log.debug(message) if worker_log.present? && app_debug_enabled?
    end

    def find_worker_log(job_id)
      return if job_id.blank?
      FileUtils.mkdir_p(CapistranoMulticonfigParallel.log_directory) unless File.directory?(CapistranoMulticonfigParallel.log_directory)
      filename = File.join(CapistranoMulticonfigParallel.log_directory, "worker_#{job_id}.log")
      worker_log = ::Logger.new(filename)
      worker_log.level = ::Logger::Severity::DEBUG
      worker_log.formatter = proc do |severity, datetime, progname, msg|
        date_format = datetime.strftime('%Y-%m-%d %H:%M:%S')
        "[#{date_format}] #{severity}  (#{progname}): #{msg}\n"
      end
      worker_log
    end

    def debug_websocket?
      websocket_config['enable_debug'].to_s == 'true'
    end

    def websocket_config
      config = app_configuration[:websocket_server]
      config.present? && config.is_a?(Hash) ? config.stringify_keys : {}
      config['enable_debug'] = config.fetch('enable_debug', '').to_s == 'true'
      config
    end
  end
end
