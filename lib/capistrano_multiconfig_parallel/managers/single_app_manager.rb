require_relative './base_manager'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class SingleAppManager < CapistranoMulticonfigParallel::BaseManager
    include Celluloid
    include Celluloid::Logger

    def run_normal_command(options)
      collect_jobs(options) do |new_options|
        deploy_app(new_options)
      end
    end

    def run_custom_command(options)
      stages = fetch_multi_stages
      return if stages.blank?
      stages = check_multi_stages(stages)
      collect_jobs(options) do |new_options|
        stages.each do |stage|
          deploy_app(new_options.merge('stage' => stage))
        end
      end
    end
  end
end
