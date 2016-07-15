require_relative './celluloid_worker'
require_relative './process_runner'
require_relative '../classes/runner_status'
module CapistranoMulticonfigParallel
  class BundlerWorker
    include CapistranoMulticonfigParallel::BaseActorHelper

    def work(job, options = {}, &callback)
      @job = job
      @options = options.symbolize_keys
      @job_id = job.id
      @runner_status = nil
      check_missing_deps
    end

    def actor_id
      "bundler_worker_#{@job_id}".to_sym
    end

    def check_missing_deps
      command = @job.fetch_bundler_worker_command
      log_to_file("bundler worker #{@job_id} executes: #{command}")
      do_bundle_sync_command(command)
    end

    def do_bundle_sync_command(command)
      CapistranoMulticonfigParallel::ProcessRunner.supervise as: actor_id
      result =  Celluloid::Actor[actor_id].work(@job, command,sync: :sync, :callback => lambda { |runner_status| @runner_status = runner_status } )
      sleep(0.1) until @runner_status.present?
      @runner_status.output_text.include?("The Gemfile's dependencies are satisfied")
    end

  end
end
