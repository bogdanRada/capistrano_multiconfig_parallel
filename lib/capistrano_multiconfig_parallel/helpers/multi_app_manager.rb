require_relative './base_manager'
require_relative '../multi_app_helpers/dependency_tracker'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class MultiAppManager < CapistranoMulticonfigParallel::BaseManager
    include Celluloid
    include Celluloid::Logger

    def initialize(cap_app, top_level_tasks, stages)
      super(cap_app, top_level_tasks, stages)
      @dependency_tracker = CapistranoMulticonfigParallel::DependencyTracker.new(Actor.current)
    end

    def check_before_starting
      verify_app_dependencies(@stages) if configuration.present? && configuration.track_dependencies.to_s.downcase == 'true'
      super
    end

    def verify_app_dependencies(stages)
      applications = stages.map { |stage| stage.split(':').reverse[1] }
      wrong = configuration.application_dependencies.find do |hash|
        !applications.include?(hash[:app]) || (hash[:dependencies].present? && hash[:dependencies].find { |val| !applications.include?(val) })
      end
      raise ArgumentError, "invalid configuration for #{wrong.inspect}" if wrong.present?
    end
    
    def run
      options = {}
      if custom_command?
        run_custom_command(options)
      else
        menu_deploy_interactive(options)
      end
      process_jobs
    end

    def run_custom_command(options)
      return unless custom_command?
      CapistranoMulticonfigParallel.interactive_menu = true
      options[:action] = @argv['ACTION'].present? ? @argv['ACTION'].present? : 'deploy'
      action_name = @name
      if  action_name == custom_commands[:stages]
        multi_stage_deploy(options)
      else
        raise "Custom command #{@name} not available for multi apps"
      end
    end

    def multi_stage_deploy(options)
      stages = fetch_multi_stages
      return if stages.blank?
      stages = check_multi_stages(stages)
      multi_collect_and_run_jobs(options) do |apps, new_options|
        apps.each do |app|
          stages.each do |stage|
            deploy_app(new_options.merge('app' => app, 'stage' => stage))
          end
        end if apps.present?
      end
    end

    def menu_deploy_interactive(options)
      multi_collect_and_run_jobs(options) do |apps, new_options|
        deploy_multiple_apps(apps, new_options)
        deploy_app(new_options) if !custom_command? && new_options['app'].present?
      end
    end

    private

    def multi_collect_and_run_jobs(options = {}, &block)
      collect_jobs(options) do |new_options|
        applications = @dependency_tracker.fetch_apps_needed_for_deployment(new_options['app'], new_options['action'])
        backup_the_branch
        block.call(applications, new_options) if block_given?
      end
    end

    def backup_the_branch
      return if custom_command? || @argv['BRANCH'].blank?
      @branch_backup = @argv['BRANCH'].to_s
      @argv['BRANCH'] = nil
    end

    def deploy_multiple_apps(applications, options)
      options = options.stringify_keys
      return unless applications.present?
      applications.each do |app|
        deploy_app(options.merge('app' => app))
      end
    end
  end
end
