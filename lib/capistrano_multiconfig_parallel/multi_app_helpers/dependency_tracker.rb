require_relative './interactive_menu'

module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class DependencyTracker
    attr_accessor :job_manager

    def initialize(job_manager)
      @job_manager = job_manager
    end

    def application_dependencies
      deps = CapistranoMulticonfigParallel.configuration.track_dependencies ? CapistranoMulticonfigParallel.configuration.application_dependencies : []
      deps.present? && deps.is_a?(Array) ? deps.map(&:stringify_keys) : []
    end

    def all_websites_return_applications_selected
      applications = application_dependencies.map { |hash| hash['app'].camelcase }
      applications << 'all_frameworks'
      interactive_menu = CapistranoMulticonfigParallel::InteractiveMenu.new
      applications_selected = interactive_menu.show_all_websites_interactive_menu(applications)
      applications_selected = applications_selected.gsub("\r\n", '') if applications_selected.present?
      applications_selected = applications_selected.delete("\n") if applications_selected.present?
      applications_selected = applications_selected.split(',') if applications_selected.present?
      applications_selected.present? ? applications_selected : []
    end

    def add_dependency_app(app_to_deploy, apps_dependencies, applications_to_deploy)
      return unless app_to_deploy.present?
      applications_to_deploy << app_to_deploy
      return unless app_to_deploy['dependencies'].present?
      app_to_deploy['dependencies'].each do |dependency|
        dependency_app = application_dependencies.find { |hash| hash['app'] == dependency }
        apps_dependencies << dependency_app if dependency_app.present?
      end
    end

    def find_apps_and_deps(applications_selected)
      applications_to_deploy = []
      apps_dependencies = []
      applications_selected.each do |app|
        app_to_deploy = application_dependencies.find { |hash| hash['app'].camelcase == app }
        add_dependency_app(app_to_deploy, apps_dependencies, applications_to_deploy)
      end
      [applications_to_deploy, apps_dependencies]
    end

    def check_app_dependency_unique(applications_selected, apps_dependencies, applications_to_deploy, action)
      return applications_to_deploy if applications_selected.blank? || apps_dependencies.blank? || (apps_dependencies.map { |app| app['app'] } - applications_to_deploy.map { |app| app['app'] }).blank?
      set :apps_dependency_confirmation, CapistranoMulticonfigParallel.ask_confirm("Do you want to  #{action} all dependencies also ?", 'Y/N')
      applications_to_deploy = applications_to_deploy.concat(apps_dependencies) if fetch(:apps_dependency_confirmation).present? && fetch(:apps_dependency_confirmation).downcase == 'y'
      applications_to_deploy
    end

    def get_applications_to_deploy(action, applications_selected)
      all_frameworks = applications_selected.find { |app| app == 'all_frameworks' }
      if all_frameworks.present?
        applications_to_deploy = application_dependencies.map { |hash| hash }
      else
        applications_to_deploy, apps_dependencies = find_apps_and_deps(applications_selected)
        applications_to_deploy = check_app_dependency_unique(applications_selected, apps_dependencies, applications_to_deploy, action)
      end
      if applications_to_deploy.present?
        applications_to_deploy = applications_to_deploy.uniq
        applications_to_deploy = applications_to_deploy.sort_by { |hash| hash['priority'] }
      end
      show_frameworks_used(applications_to_deploy, all_frameworks, action)
    end

    def show_frameworks_used(applications_to_deploy, all_frameworks, action)
      return [] if applications_to_deploy.blank? || applications_to_deploy.size < 1
      puts 'The following frameworks will be used:'
      app_names = []
      if all_frameworks.present?
        app_names = applications_to_deploy.map { |app| app['app'].camelcase }
      else
        app_names = applications_to_deploy.map { |app| application_dependencies.find { |hash| hash['app'] == app['app'] }['app'].camelcase }
      end
      print_frameworks_used(app_names, applications_to_deploy, action)
    end

    def print_frameworks_used(app_names, applications_to_deploy, action)
      app_names.each { |app| puts "#{app}" }
      set :apps_deploy_confirmation, CapistranoMulticonfigParallel.ask_confirm("Are you sure you want to #{action} these apps?", 'Y/N')
      if fetch(:apps_deploy_confirmation).blank? || (fetch(:apps_deploy_confirmation).present? && fetch(:apps_deploy_confirmation).downcase != 'y')
        return []
      elsif fetch(:apps_deploy_confirmation).present? && fetch(:apps_deploy_confirmation).downcase == 'y'
        return applications_to_deploy
      end
    end

    def fetch_apps_needed_for_deployment(application, action)
      applications = []
      if @job_manager.custom_command? && @job_manager.multi_apps?
        apps_selected = all_websites_return_applications_selected
        applications = get_applications_to_deploy(action, apps_selected)
      elsif CapistranoMulticonfigParallel.configuration.track_dependencies
        if application.present?
          applications = get_applications_to_deploy(action, [application.camelcase])
          applications = applications.delete_if { |hash| hash['app'] == application }
        else
          applications = []
        end
      else
        applications = []
      end
      applications
    end
  end
end
