require_relative '../helpers/base_actor_helper'
module CapistranoMulticonfigParallel
  class ProcessRunner
    include CapistranoMulticonfigParallel::BaseActorHelper

    @attrs = [
      :options,
      :job,
      :cmd,
      :runner_status_klass,
      :runner_status,
      :actor,
      :job_id,
      :timer,
      :synchronicity
    ]

    attr_reader *@attrs
    attr_accessor *@attrs

    finalizer :process_finalizer

    def work(job, cmd, options = {})
      @options = options.is_a?(Hash) ? options.symbolize_keys : {}
      @job = job
      @cmd = cmd

      @runner_status_klass = @options[:runner_status_klass].present? ? @options[:runner_status_klass] : RunnerStatus
      @runner_status = @runner_status_klass.new(Actor.current, job, cmd,  @options)
      @synchronicity = @options[:process_sync]
      start_running
    end

    def start_running
      setup_attributes
      run_right_popen3
      setup_em_error_handler
    end

    def setup_attributes
      @actor = @options.fetch(:actor, nil)
      @job_id = @job.id
    end

    def setup_em_error_handler
      EM.error_handler do|exception|
        log_error(exception, job_id: @job_id, output: 'stderr')
        EM.stop
      end
    end

    def setup_periodic_timer
      @timer = EM::PeriodicTimer.new(0.1) do
        check_exit_status
        @timer.cancel if @runner_status.exit_status.present?
      end
    end

    def check_exit_status
      exit_status = @runner_status.exit_status
      return if exit_status.blank?
      @timer.cancel
      log_to_file("worker #{@job_id} startsnotify finished with exit status #{exit_status.inspect}")
      if @actor.present? && @actor.respond_to?(:notify_finished)
        if @actor.respond_to?(:async) && @synchronicity == :async
          @actor.async.notify_finished(exit_status, @runner_status)
        else
          @actor.notify_finished(exit_status, @runner_status)
        end
      end
    end

    def process_finalizer
      EM.stop if EM.reactor_running?
      terminate
    end

    def run_right_popen3
      popen3_options = {
        #  :timeout_seconds  => @options.has_key?(:timeout) ? @options[:timeout] : 2,
        :size_limit_bytes => @options[:size_limit_bytes],
        :watch_directory  => @options[:watch_directory],
        :user             => @options[:user],
        :group            => @options[:group],
      }
      command = @runner_status.command
      case @synchronicity
      when :sync
        run_right_popen3_sync(command, popen3_options)
      when :async
        run_right_popen3_async(command, popen3_options)
      else
        raise "unknown synchronicity = #{synchronicity.inspect}"
      end
    end

    def run_right_popen3_sync(command, popen3_options)
      do_right_popen3_sync(command, popen3_options)
    end

    def run_right_popen3_async(command, popen3_options)
      EM.run do
        EM.defer do
          begin
            do_right_popen3_async(command, popen3_options)
          rescue Exception => e
            log_error(exception, job_id: @job_id, output: 'stderr')
            EM.stop
          end
        end
        setup_periodic_timer
      end
    end

    def do_right_popen3(synchronicity, command, popen3_options)
      popen3_options = {
        :target                  => @runner_status,
        :environment             => @options.fetch(:environment, nil),
        :input                   => :on_input_stdin,
        :stdout_handler          => :on_read_stdout,
        :stderr_handler          => :on_read_stderr,
        :watch_handler           => :watch_handler,
        :pid_handler             => :on_pid,
        :timeout_handler         => :on_timeout,
        :size_limit_handler      => :on_size_limit,
        :exit_handler            => :on_exit,
        :async_exception_handler => :async_exception_handler
      }.merge(popen3_options)
      case synchronicity
      when :sync
        result = ::RightScale::RightPopen.popen3_sync(command, popen3_options)
      when :async
        result = ::RightScale::RightPopen.popen3_async(command, popen3_options)
      else
        raise "Uknown synchronicity = #{synchronicity.inspect}"
      end
      result == true
    end

    def do_right_popen3_sync(command, popen3_options)
      do_right_popen3(:sync, command, popen3_options)
    end

    def do_right_popen3_async( command, popen3_options)
      do_right_popen3(:async, command, popen3_options)
    end

  end
end
