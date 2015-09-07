module CapistranoMulticonfigParallel
  # class that is used to execute the capistrano tasks and it is invoked by the celluloid worker
  class ChildProcess
    include Celluloid
    include Celluloid::Logger

    attr_accessor :actor, :pid, :exit_status, :process, :filename, :worker_log, :job_id, :debug_enabled

    finalizer :process_finalizer

    def work(cmd, options = {})
      @options = options
      @actor = @options.fetch(:actor, nil)
      @job_id = @actor.job_id
      @debug_enabled = @actor.debug_enabled?
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
        @worker_log.debug "Error during event loop for worker #{@job_id}: #{e.inspect}" if @debug_enabled
        @worker_log.debug e.backtrace if @debug_enabled
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

    def process_finalizer
      @timer.cancel
      EM.stop if EM.reactor_running?
    end

    def check_exit_status
      return unless @exit_status.present?
      if @exit_status.exitstatus == 0 && @options[:dry_run]
        debug("worker #{@actor.job_id} starts execute deploy") if @debug_enabled
        @actor.async.execute_deploy
      elsif !@actor.worker_finshed?
        debug("worker #{@actor.job_id} startsnotify finished") if @debug_enabled
        @actor.notify_finished(@exit_status)
      end
    end

    def start_async_deploy(cmd, options)
      RightScale::RightPopen.popen3_async(
        cmd,
        target: self,
        environment: options[:environment].present? ? options[:environment] : nil,
        pid_handler: :on_pid,
        input: :on_input_stdin,
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
      @worker_log.debug "Child process for worker #{@job_id} on_exit  disconnected due to error #{status.inspect}" if @debug_enabled
      @exit_status = status
    end

    def async_exception_handler(*data)
      @worker_log.debug "Child process for worker #{@job_id} async_exception_handler  disconnected due to error #{data.inspect}" if @debug_enabled
      io_callback('stderr', data)
      @exit_status = 1
    end

    def watch_handler(process)
      @process ||= process
    end

    def io_callback(io, data)
      @worker_log.debug("#{io.upcase} ---- #{data}")
    end
  end
end
