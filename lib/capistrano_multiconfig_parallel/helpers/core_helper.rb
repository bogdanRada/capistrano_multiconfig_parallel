module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module CoreHelper
  module_function

    def multi_fetch_argv(args)
      options = {}
      args.each do |arg|
        if arg =~ /^(\w+)=(.*)$/m
          options[Regexp.last_match(1)] = Regexp.last_match(2)
        end
      end
      options
    end

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

    def error_filtered?(error)
      [CapistranoMulticonfigParallel::TaskFailed, SystemExit].find { |class_name| error.is_a?(class_name) }.present?
    end

    def development_debug?
      ENV['MULTICAP_DEBUG'].to_s == 'true'
    end

    def log_error(error, options = {})
      message = format_error(error)
      log_output_error(error, options.fetch(:output, nil), message)
      log_to_file(message, options.merge(log_method: 'fatal'))
    end

    def terminal_actor
      Celluloid::Actor[:terminal_server]
    end

    def terminal_errors?
      development_debug? && terminal_actor.present? && terminal_actor.alive? && terminal_actor.errors.is_a?(Array)
    end

    def log_output_error(error, output, message)
      return if message.blank? || error_filtered?(error)
      puts message if output.present?
      terminal_actor.errors.push(message) if terminal_errors?
    end

    def format_error(exception)
      message = "\n#{exception.class} (#{exception.respond_to?(:message) ? exception.message : exception.inspect}):\n"
      message << exception.annoted_source_code.to_s if exception.respond_to?(:annoted_source_code)
      message << '  ' << exception.backtrace.join("\n  ") if exception.respond_to?(:backtrace)
      message
    end

    def log_to_file(message, options = {})
      worker_log = options.fetch(:job_id, '').present? ? find_worker_log(options[:job_id], options[:prefix]) : logger
      print_to_log_file(worker_log, options.merge(message: message)) if worker_log.present? && app_debug_enabled?
    end

    def print_to_log_file(worker_log, options = {})
      worker_log.send(options.fetch(:log_method, 'debug'), "#{options.fetch(:message, '')}\n")
    end

    def find_worker_log(job_id, prefix = nil)
      return if job_id.blank?
      FileUtils.mkdir_p(log_directory) unless File.directory?(log_directory)
      filename = File.join(log_directory, "multi_cap_worker_#{prefix.present? ? "#{prefix}_" : ''}#{job_id}.log")
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
      create_log_file(websocket_server_config.fetch('log_file_path', nil)) if debug_websocket?
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
      log_error(error, output: output)
      exit(1)
    end

    def rescue_interrupt
      `stty icanon echo`
      puts "\n Command was cancelled due to an Interrupt error."
    end
  end
end
