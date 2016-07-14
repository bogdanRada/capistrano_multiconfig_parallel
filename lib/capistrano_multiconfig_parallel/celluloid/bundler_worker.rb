require_relative './celluloid_worker'
module CapistranoMulticonfigParallel
  class BundlerWorker < CapistranoMulticonfigParallel::CelluloidWorker
    include CapistranoMulticonfigParallel::BaseActorHelper

    def work(job, options = {}, &callback)
      @job = job
      @options = options.symbolize_keys
      @job_id = job.id
      check_missing_deps
      ends

      def check_missing_deps
        command = @job.fetch_bundler_check_command
        log_to_file("bundler worker #{@job_id} executes: #{command}")
        do_bundle_sync_command(command)
      end


      def do_bundle_sync_command(command)
        RightScale::RightPopen.popen3_sync(
        command,
        target: self,
        environment: @options.fetch(:environment, nil),
        :stdout_handler          => :on_read_stdout,
        :stderr_handler          => :on_read_stderr,
        :pid_handler             => :on_pid,
        :timeout_handler         => :on_timeout,
        :size_limit_handler      => :on_size_limit,
        :exit_handler            => :on_exit,
        :async_exception_handler => :on_async_exception

        input: :on_input_stdin,
        watch_handler: :watch_handler
      )
      end





    end
  end
