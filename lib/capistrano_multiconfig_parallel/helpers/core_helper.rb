module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module CoreHelper
  module_function

    def app_debug_enabled?
      configuration.multi_debug.to_s.downcase == 'true'
    end

    def show_warning(message)
      warn message if app_debug_enabled?
    end

    def check_terminal_tty
      $stdin.sync = true if $stdin.isatty
      $stdout.sync = true if $stdout.isatty
    end

    def find_loaded_gem(name)
      Gem.loaded_specs.values.find { |repo| repo.name == name }
    end

    def ask_stdout_confirmation(message, default)
      result = Ask.input message, default: default
      $stdout.flush
      result
    end

    def ask_confirm(message, default)
      force_confirmation do
        ask_stdout_confirmation(message, default)
      end
    rescue
      return nil
    end

    def force_confirmation(&block)
      `stty -raw echo`
      check_terminal_tty
      result = block.call
      `stty -raw echo`
      result
    end

    def filtered_errors
      [CapistranoMulticonfigParallel::CelluloidWorker::TaskFailed, Celluloid::DeadActorError, Celluloid::Task::TerminatedError]
    end

    def error_filtered?(error)
      filtered_errors.find { |class_name| error.is_a?(class_name) }.present?
    end

    def log_error(error, output = nil)
      return if error_filtered?(error)
      message = format_error(error)
      puts(message) if output.present?
      log_to_file(message)
    end

    def format_error(error)
      JSON.pretty_generate(class_name: error.class,
                           message: error.respond_to?(:message) ? error.message : error.inspect,
                           backtrace: error.respond_to?(:backtrace) ? error.backtrace.join("\n\n") : '')
    end

    def log_to_file(message, job_id = nil)
      worker_log = job_id.present? ? find_worker_log(job_id) : logger
      worker_log.debug(message) if worker_log.present? && app_debug_enabled?
    end

    def find_worker_log(job_id)
      return if job_id.blank?
      FileUtils.mkdir_p(log_directory) unless File.directory?(log_directory)
      filename = File.join(log_directory, "worker_#{job_id}.log")
      setup_filename_logger(filename)
    end

    def setup_filename_logger(filename)
      worker_log = ::Logger.new(filename)
      worker_log.level = ::Logger::Severity::DEBUG
      setup_logger_formatter(worker_log)
      worker_log
    end

    def setup_logger_formatter(logger)
      logger.formatter = proc do |severity, datetime, progname, msg|
        date_format = datetime.strftime('%Y-%m-%d %H:%M:%S')
        "[#{date_format}] #{severity}  (#{progname}): #{msg}\n"
      end
    end

    def debug_websocket?
      websocket_server_config['enable_debug'].to_s == 'true'
    end

    def websocket_server_config
      configuration.fetch(:websocket_server, {}).stringify_keys
    end

    def websocket_config
      websocket_server_config.merge('enable_debug' =>  debug_websocket?)
    end

    def execute_with_rescue(output = nil)
      yield if block_given?
    rescue Interrupt
      rescue_interrupt
    rescue => error
      rescue_error(error, output)
    end

    def rescue_error(error, output = nil)
      log_error(error, output)
      exit(1)
    end

    def rescue_interrupt
      `stty icanon echo`
      puts "\n Command was cancelled due to an Interrupt error."
    end
  end
end
