require_relative './celluloid_worker'
require_relative './process_runner'
require_relative '../classes/bundler_status'
module CapistranoMulticonfigParallel
  class BundlerWorker
    include CapistranoMulticonfigParallel::BaseActorHelper

    attr_reader *[
      :job,
      :job_id,
      :runner_status,
      :log_prefix,
      :checked_bundler_deps,
      :total_dependencies,
      :show_bundler
    ]

    def work(job)
      @job = job
      @job_id = job.id
      @runner_status = nil
      @log_prefix = 'bundler'
      @checked_bundler_deps = []
      @total_dependencies = bundler_dependencies.size
      @show_bundler = true
      progress_bar
      check_missing_deps
    end

    def progress_bar
      @progress_bar ||= ProgressBar.create(:title => "Checking app #{File.basename(@job.job_path)} bundler dependencies ", :starting_at => 0, :total => @total_dependencies.to_i, length: 160, :format => '%a |%b>>%i| %p%% %t | Processed: %c from %C gem dependencies')
    end

    def bundler_dependencies
      builder = Bundler::Dsl.new
      builder.eval_gemfile(@job.job_gemfile)
      definition = builder.to_definition(@job.job_gemfile_lock, {})
      @bundler_dependencies ||= definition.dependencies
    end

    def show_bundler_progress(data)
      @show_bundler = false if  data.to_s.include?("The Gemfile's dependencies are satisfied") || data.to_s.include?("Bundle complete")
      gem_spec = bundler_dependencies.find{|spec| data.include?(spec.name) }
      if  @show_bundler == true && gem_spec.present?
        @checked_bundler_deps = [gem_spec.name]
        progress_bar.increment
      elsif @show_bundler == false
        progress_bar.finish
      end
    end

    def check_missing_deps
      command = @job.fetch_bundler_worker_command
      log_to_file("bundler worker #{@job_id} executes: #{command}", job_id: @job_id, prefix: @log_prefix)
      do_bundle_sync_command(command)
    end

    def do_bundle_sync_command(command)
      process_runner = CapistranoMulticonfigParallel::ProcessRunner.new
      process_runner.work(@job, command, process_sync: :sync, actor: Actor.current, log_prefix: @log_prefix, runner_status_klass: CapistranoMulticonfigParallel::BundlerStatus, :callback => lambda {|runner_status| @runner_status = runner_status })
      sleep(0.1) until @runner_status.present?
      @runner_status.output_text
    end


  end
end
