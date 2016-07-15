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
      :count,
      :done,
      :last_exception,
      :last_iteration,
      :callback,
      :synchronicity,
      :iterations,
      :repeats,
      :stats
    ]

    attr_reader *@attrs
    attr_accessor *@attrs

    finalizer :process_finalizer

    def work(job, cmd, options = {})
      @count          = 0
      @done           = false
      @last_exception = nil
      @last_iteration = 0
      @callback = options[:callback].present? ? options[:callback] : nil

      @options = options.is_a?(Hash) ? options.symbolize_keys : {}
      @job = job
      @cmd = cmd
      @runner_status_klass = @options[:runner_status_klass].present? ? @options[:runner_status_klass] : RunnerStatus
      @runner_status = @runner_status_klass.new(Actor.current, job, cmd,  @options)
      @synchronicity = @options[:sync]
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
      return if @runner_status.exit_status.blank?
      @timer.cancel
      @job.exit_status = @runner_status.exit_status
      log_to_file("worker #{@job_id} startsnotify finished with exit status #{@job.exit_status.inspect}")
      if @actor.present? && @actor.respond_to?(:notify_finished)
        if @actor.respond_to?(:async) && @synchronicity == :async
          @actor.async.notify_finished(@job.exit_status)
        elsif @synchronicity == :sync
          @actor.notify_finished(@job.exit_status)
        end
      end
    end

    def process_finalizer
      EM.stop if EM.reactor_running?
      terminate
    end

    def run_right_popen3
      runner_options = {
        :repeats           => 1,
        :expect_timeout    => false,
        :expect_size_limit => false
      }.merge(@runner_status.options)
      popen3_options = {
      #  :timeout_seconds  => runner_options.has_key?(:timeout) ? runner_options[:timeout] : 2,
        :size_limit_bytes => runner_options[:size_limit_bytes],
        :watch_directory  => runner_options[:watch_directory],
        :user             => runner_options[:user],
        :group            => runner_options[:group],
      }
      command = @runner_status.command
      callback = @callback
      case @synchronicity
      when :sync
        run_right_popen3_sync(command, runner_options, popen3_options, &callback)
      when :async
        run_right_popen3_async(command, runner_options, popen3_options, &callback)
      else
        raise "unknown synchronicity = #{synchronicity.inspect}"
      end
    end

    def run_right_popen3_sync(command, runner_options, popen3_options, &callback)
      @iterations = 0
      @repeats = runner_options[:repeats]
      @stats = []
      while @iterations < @repeats
        @iterations += 1
        do_right_popen3_sync(command, runner_status, runner_options, popen3_options) do |runner_status|
          @stats << runner_status
          callback.call(runner_status) if callback
          if @repeats > 1
            puts if 1 == (@iterations % 64)
            print '+'
            puts if @iterations == @repeats
          end
        end
      end
      @stats.uniq!
      @stats.size < 2 ? @stats.first : @stats
    end

    def run_right_popen3_async(command, runner_options, popen3_options, &callback)
      @iterations = 0
      @repeats = runner_options[:repeats]
      @stats = []
      last_exception = nil
      EM.run do
        EM.defer do
          begin
            do_right_popen3_async(command, runner_options, popen3_options) do |runner_status_callback|
              raise runner_status_callback.inspect
              last_exception ||= maybe_continue_popen3_async(runner_status_callback, command, runner_options, popen3_options, &callback)
            end
          rescue Exception => e
            last_exception = e
            EM.stop
          end
        end
        setup_periodic_timer
      end
      raise last_exception if last_exception
      @stats.uniq!
      @stats.size < 2 ? @stats.first : @stats
    end

    def do_right_popen3(synchronicity, command,   runner_options, popen3_options)
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

    def do_right_popen3_sync(command, runner_options, popen3_options, &callback)
      do_right_popen3(:sync, command, runner_options, popen3_options, &callback)
    end

    def do_right_popen3_async( command, runner_options, popen3_options, &callback)
      do_right_popen3(:async, command, runner_options, popen3_options, &callback)
    end

    def maybe_continue_popen3_async(runner_status, command, runner_options, popen3_options, &callback)
      @iterations += 1
      @stats << runner_status
      callback.call(runner_status) if callback
      last_exception = nil
      if @iterations < @repeats
        if @repeats > 1
          puts if 1 == (@iterations % 64)
          print '+'
          puts if @iterations == @repeats
        end
        EM.defer do
          begin
            do_right_popen3_async(command, runner_options, popen3_options) do |runner_status2|
              last_exception ||= maybe_continue_popen3_async(runner_status2, command,  runner_options, popen3_options, &callback)
            end
          rescue Exception => e
            last_exception = e
            EM.stop
          end
        end
      else
        EM.stop
      end
      last_exception ||= runner_status.async_exception
      last_exception
    end
  end
end
