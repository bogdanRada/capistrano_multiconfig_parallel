require_relative '../helpers/application_helper'
require_relative '../helpers/core_helper'
module CapistranoMulticonfigParallel
  # class that is used to execute the capistrano tasks and it is invoked by the celluloid worker
  class ChildProcess
    include Celluloid
    include Celluloid::Logger
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_accessor :options, :job, :actor, :job_id, :exit_status, :pid, :process

    finalizer :process_finalizer

    def work(job, cmd, options = {})
      @options = options
      @job = job
      @cmd = cmd
      start_running
    end

    def start_running
      setup_attributes
      run_event_machine
      setup_em_error_handler
    end

    def setup_attributes
      @actor = @options.fetch(:actor, nil)
      @job_id = @job.id
      @exit_status = nil
    end

    def setup_em_error_handler
      EM.error_handler do|exception|
        log_to_file("Error during event loop for worker #{@job_id}: #{format_error(exception)}", job_id: @job_id)
        EM.stop
      end
    end

    def run_event_machine
      EM.run do
        EM.next_tick do
          start_async_deploy
        end
        setup_periodic_timer
      end
    end

    def setup_periodic_timer
      @timer = EM::PeriodicTimer.new(0.1) do
        check_exit_status
        @timer.cancel if @exit_status.present?
      end
    end

    def process_finalizer
      EM.stop if EM.reactor_running?
      terminate
    end

    def check_exit_status
      return if @exit_status.blank?
      @timer.cancel
      @job.exit_status = @exit_status
      log_to_file("worker #{@job_id} startsnotify finished with exit status #{@exit_status.inspect}")
      @actor.async.notify_finished(@exit_status)
    end

    def start_async_deploy
      RightScale::RightPopen.popen3_async(
        @cmd,
        target: self,
        environment: @options.fetch(:environment, nil),
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
      log_to_file "Child process for worker #{@job_id} on_exit  disconnected due to error #{status.inspect}"
      @exit_status = status.exitstatus
      check_exit_status
    end

    def async_exception_handler(*data)
      log_to_file "Child process for worker #{@job_id} async_exception_handler  disconnected due to error #{data.inspect}"
      io_callback('stderr', data)
      @exit_status = 1
      check_exit_status
    end

    def watch_handler(process)
      @process ||= process
      check_exit_status
    end

    def io_callback(io, data)
      log_to_file("#{io.upcase} ---- #{data}", job_id: @job_id)
    end
  end
end
