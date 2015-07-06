module CapistranoMulticonfigParallel
  # class that is used to execute the capistrano tasks and it is invoked by the celluloid worker
  class ChildProcess
    include Celluloid
    include Celluloid::Logger

    attr_accessor :actor, :pid, :exit_status, :process, :filename, :worker_log

    def work(cmd, options = {})
      @options = options
      @actor = @options.fetch(:actor, nil)
      set_worker_log
      EM.run do
        EM.next_tick do
          start_async_deploy(cmd, options)
        end
        @timer = EM::PeriodicTimer.new(0.1) do
          check_exit_status
        end
      end
      EM.error_handler do|e|
        puts "Error during event loop for worker #{@actor.job_id}: #{e.inspect}" if @actor.debug_enabled?
        puts e.backtrace if @actor.debug_enabled?
        EM.stop
      end
    end

    def set_worker_log
      FileUtils.mkdir_p(CapistranoMulticonfigParallel.log_directory) unless File.directory?(CapistranoMulticonfigParallel.log_directory)
      @filename = File.join(CapistranoMulticonfigParallel.log_directory, "worker_#{@actor.job_id}.log")
      FileUtils.rm_rf(@filename) if File.file?(@filename) && !@actor.crashed? && (@options[:dry_run] || @actor.executed_dry_run != true)
      @worker_log = ::Logger.new(@filename)
      @worker_log.level = ::Logger::Severity::DEBUG
      @worker_log.formatter = proc do |severity, datetime, progname, msg|
        date_format = datetime.strftime('%Y-%m-%d %H:%M:%S')
        "[#{date_format}] #{severity}  (#{progname}): #{msg}\n"
      end
    end

    def check_exit_status
      return unless @exit_status.present?
      @timer.cancel
      EM.stop
      if @options[:dry_run]
        debug("worker #{@actor.job_id} starts execute deploy") if @actor.debug_enabled?
        @actor.async.execute_deploy
      else
        debug("worker #{@actor.job_id} startsnotify finished") if @actor.debug_enabled?
        @actor.notify_finished(@exit_status)
      end
    end

    def start_async_deploy(cmd, options)
      RightScale::RightPopen.popen3_async(
        cmd,
        target: self,
        environment: options[:environment].present? ? options[:environment] : nil,
        pid_handler: :on_pid,
        stdout_handler: :on_read_stdout,
        stderr_handler: :on_read_stderr,
        watch_handler: :watch_handler,
        async_exception_handler: :async_exception_handler,
        exit_handler: :on_exit)
    end

    def on_pid(pid)
      @pid ||= pid
    end

    def on_input_stdin(data)
      io_callback('stdin', data)
    end

    def on_read_stdout(data)
      io_callback('stdout', data)
    end

    def on_read_stderr(data)
      io_callback('stderr', data)
    end

    def on_exit(status)
      debug "Child process for worker #{@actor.job_id} on_exit  disconnected due to error #{status.inspect}" if @actor.debug_enabled?
      @exit_status = status
    end

    def async_exception_handler(*data)
      debug "Child process for worker #{@actor.job_id} async_exception_handler  disconnected due to error #{data.inspect}" if @actor.debug_enabled?
      io_callback('stderr', data)
      @exit_status = 1
    end

    def watch_handler(process)
      @process ||= process
    end

    def get_question_details(data)
      question = ''
      default = nil
      if data =~ /(.*)\?+\s*\:*\s*(\([^)]*\))*/m
        question = Regexp.last_match(1)
        default = Regexp.last_match(2)
      end
      question.present? ? [question, default] : nil
    end

    def printing_question?(data)
      get_question_details(data).present?
    end

    def user_prompt_needed?(data)
      return unless printing_question?(data)
      details = get_question_details(data)
      default = details.second.present? ? details.second : nil
      result = CapistranoMulticonfigParallel.ask_confirm(details.first, default)
      @actor.publish_io_event(result)
    end

    def io_callback(io, data)
      @worker_log.debug("#{io.upcase} ---- #{data}")
      user_prompt_needed?(data)
    end
  end
end
