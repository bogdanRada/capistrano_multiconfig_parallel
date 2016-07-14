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
        runner = CapistranoMulticonfigParallel::Runner.new
        runner.run_right_popen3(:sync, command)
      end





    end
  end
