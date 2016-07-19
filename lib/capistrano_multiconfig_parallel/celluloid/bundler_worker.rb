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
      @job.application.bundler_workers_store[job] = Actor.current
      @job_id = job.id
      @runner_status = nil
      @log_prefix = 'bundler'
      @checked_bundler_deps = []
      @total_dependencies = bundler_dependencies.size
      @show_bundler = true
      async.check_missing_deps
    end

    def progress_bar
      if defined?(@progress_bar)
        @progress_bar
      else
        @progress_bar ||= PowerBar.new
        @progress_bar.define_singleton_method :terminal_width do
          40
        end
        @progress_bar.settings.tty.finite.template.main = \
        "${<msg>} ${<bar> } ${<percent>%}" # + "${<rate>/s} ${<elapsed>}${ ETA: <eta>}"
        @progress_bar.settings.tty.finite.template.padchar = "#{@progress_bar.settings.tty.finite.template.padchar}"
        @progress_bar.settings.tty.finite.template.barchar = "#{@progress_bar.settings.tty.finite.template.barchar}"
        @progress_bar.settings.tty.finite.template.exit = "\e[?25h\e[0mFINISHED"  # clean up after us
        @progress_bar.settings.tty.finite.template.close = "\e[?25h\e[0mFINISHED \n" # clean up after us
        @progress_bar.settings.tty.finite.output = Proc.new{ |data|
          if data.present? && data.include?("Error") || data.include?("Installing")
            @job.bundler_check_status = data.include?("Error") ? data.to_s.red : data.to_s.green
            send_msg(CapistranoMulticonfigParallel::BundlerTerminalTable.topic, type: 'event', data: data.to_s.uncolorize )
          end
        }
        @progress_bar
      end
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
      if data.include?("Error") && @show_bundler == true && gem_spec.present?
        @checked_bundler_deps << [gem_spec.name]
        progress_bar.show(:msg => "Error installing #{gem_spec.name} (#{@checked_bundler_deps.size} from #{@total_dependencies.to_i} deps)", :done => @checked_bundler_deps.size, :total => @total_dependencies.to_i)
        error_message = "Bundler worker #{@job_id} task  failed for #{gem_spec.inspect}"
        raise(CapistranoMulticonfigParallel::TaskFailed.new(error_message), error_message)
      elsif  @show_bundler == true && gem_spec.present?
        @checked_bundler_deps << [gem_spec.name]
        progress_bar.show(:msg => "Installing #{gem_spec.name} (#{@checked_bundler_deps.size} from #{@total_dependencies.to_i} deps)", :done => @checked_bundler_deps.size, :total => @total_dependencies.to_i)
      elsif @show_bundler == false
        progress_bar.close if defined?(@progress_bar)
      end
    end

    def check_missing_deps
      command = @job.fetch_bundler_worker_command
      log_to_file("bundler worker #{@job_id} executes: #{command}", job_id: @job_id, prefix: @log_prefix)
      do_bundle_sync_command(command)
    end

    def do_bundle_sync_command(command)
      process_runner = CapistranoMulticonfigParallel::ProcessRunner.new
      process_runner.work(@job, command, process_sync: :async, actor: Actor.current, log_prefix: @log_prefix, runner_status_klass: CapistranoMulticonfigParallel::BundlerStatus)
    end

    def notify_finished(exit_status, runner_status)
      @runner_status = runner_status
      @exit_status = exit_status
      progress_bar.close if defined?(@progress_bar)
        log_to_file("bundler worker #{@job_id} notifuy finished with #{exit_status.inspect}")
      if exit_status.to_i == 0
        @job.application.add_job_to_list_of_jobs(@job)
      else
        error_message = "Bundler worker #{@job_id} task  failed with exit status #{exit_status.inspect}"
        raise(CapistranoMulticonfigParallel::TaskFailed.new(error_message), error_message)
      end
    end

    def send_msg(channel, message = nil)
      message = message.present? && message.is_a?(Hash) ? { job_id: @job_id }.merge(message) : { job_id: @job_id, message: message }
      log_to_file("worker #{@job_id} triest to send to #{channel} #{message}")
      publish channel, message
    end

  end
end
