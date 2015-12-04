module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module CoreHelper
  module_function

    def find_config_type(type)
      ['boolean'].include?(type.to_s) ? type.to_s.delete(':').to_sym : type.to_s.constantize
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

    def log_error(error)
      log_to_file(format_error(error))
    end

    def format_error(error)
      JSON.pretty_generate(class_name: error.class,
                           message: error.respond_to?(:message) ? error.message : error.inspect,
                           backtrace: error.respond_to?(:backtrace) ? error.backtrace.join("\n\n") : '')
    end

    def log_to_file(message, job_id = nil)
      worker_log = job_id.present? ? find_worker_log(job_id) : app_logger
      worker_log.debug(message) if worker_log.present? && app_debug_enabled?
    end

    def find_worker_log(job_id)
      return if job_id.blank?
      FileUtils.mkdir_p(log_directory) unless File.directory?(log_directory)
      filename = File.join(log_directory, "worker_#{job_id}.log")
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

    def execute_with_rescue(output = nil)
      yield if block_given?
    rescue Interrupt
      rescue_interrupt
    rescue => error
      rescue_error(error, output)
    end

    def rescue_error(error, output = nil)
      output.blank? ? log_error(error) : puts(format_error(error))
      exit(1)
    end

    def rescue_interrupt
      `stty icanon echo`
      puts "\n Command was cancelled due to an Interrupt error."
    end
  end
end
