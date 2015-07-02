require_relative './base_manager'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class SingleAppManager < CapistranoMulticonfigParallel::BaseManager
    include Celluloid
    include Celluloid::Logger

    def run
      options = {}
      if custom_command?
        run_custom_command(options)
      else
        deploy_single_app(options)
      end
      process_jobs
    end

    def run_custom_command(options)
      return unless custom_command?
      action_name = @name
      if action_name == custom_commands[:stages]
        stage_deploy(options)
      else
        raise "Custom command #{@name} not available for single apps"
      end
    end

    def stage_deploy(options)
      return unless custom_command?
      stages = fetch_multi_stages
      return if stages.blank?
      stages = check_multi_stages(stages)
      collect_jobs(options) do |new_options|
        stages.each do |stage|
          deploy_app(new_options.merge('stage' => stage, 'action' => 'deploy'))
        end
      end
    end

    def deploy_single_app(options)
      return if custom_command?
      collect_jobs(options) do |new_options|
        deploy_app(new_options)
      end
    end
  end
end
