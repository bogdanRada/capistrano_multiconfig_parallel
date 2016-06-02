require_relative './helpers/base_actor_helper'
module CapistranoMulticonfigParallel
  # finds app dependencies, shows menu and delegates jobs to celluloid manager
  class Application
    #include CapistranoMulticonfigParallel::BaseActorHelper
      include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :stage_apps, :top_level_tasks, :jobs, :condition, :manager, :dependency_tracker, :application, :stage, :name, :args, :argv, :default_stage

    def initialize
      Celluloid.boot unless Celluloid.running?
      CapistranoMulticonfigParallel.enable_logging
      @stage_apps = multi_apps? ? app_names_from_stages : []
      collect_command_line_tasks(CapistranoMulticonfigParallel.original_args)
      @jobs = []
    end

    def start
      verify_app_dependencies if multi_apps? && configuration.application_dependencies.present?
      initialize_data
      verify_valid_data
      check_before_starting
      run
    end

    def verify_app_dependencies
      wrong = configuration.application_dependencies.find do |hash|
        !@stage_apps.include?(hash[:app]) || (hash[:dependencies].present? && hash[:dependencies].find { |val| !@stage_apps.include?(val) })
      end
      raise ArgumentError, "Invalid configuration for #{wrong.inspect}".red if wrong.present?
    end

    def run_custom_command(options)
      custom_stages = fetch_multi_stages
      return if custom_stages.blank?
      custom_stages.each do |stage|
        collect_jobs(options.merge('stage' => stage))
      end
    end

    def deploy_multiple_apps(applications, options)
      options = options.stringify_keys
      return unless applications.present?
      applications.each do |app|
        deploy_app(options.merge('app' => app['app'], 'path' => app.fetch('path', nil)))
      end
    end

    def custom_command?
      custom_commands.include?(@top_level_tasks.first)
    end

    def verify_valid_data
     return if  @top_level_tasks != ['default']
     raise_invalid_job_config
    end

    def raise_invalid_job_config
        puts 'Invalid execution, please call something such as `multi_cap production deploy`, where production is a stage you have defined'.red
        exit(false)
    end

    def initialize_data
      @application = custom_command? ? nil : @top_level_tasks.first.split(':').reverse[1]
      @stage = custom_command? ? nil : @top_level_tasks.first.split(':').reverse[0]
      @stage = @stage.present? ? @stage : @default_stage
      @name, @args = parse_task_string(@top_level_tasks.second)
    end

    def collect_command_line_tasks(args) # :nodoc:
      @argv = {}
      @top_level_tasks = []
      args.each do |arg|
        if arg =~ /^(\w+)=(.*)$/m
          @argv[Regexp.last_match(1)] = Regexp.last_match(2)
        else
          @top_level_tasks << arg unless arg =~ /^-/
        end
      end
      @top_level_tasks.push(Rake.application.default_task_name) if @top_level_tasks.blank?
    end

    def action_key
      'ACTION'
    end

    def verify_options_custom_command(options)
      options[:action] = @argv[action_key].present? ? @argv[action_key] : 'deploy'
      options
    end

    def check_before_starting
      @dependency_tracker = CapistranoMulticonfigParallel::DependencyTracker.new(self)
      @default_stage = configuration.development_stages.present? ? configuration.development_stages.first : 'development'
      @condition = Celluloid::Condition.new
      @manager = CapistranoMulticonfigParallel::CelluloidManager.new(self)
    end

    def collect_jobs(options = {}, &_block)
      options = prepare_options(options)
      options = options.stringify_keys
      apps, app_options = @dependency_tracker.fetch_apps_needed_for_deployment(options['app'], options['action'])
      deploy_multiple_apps(apps, options)
      deploy_app(options.merge(app_options)) if !custom_command? || !multi_apps?
    end

    def process_jobs
      return unless @jobs.present?
      FileUtils.rm Dir["#{log_directory}/worker_*.log"]
      if configuration.multi_secvential.to_s.downcase == 'true'
        @jobs.each(&:execute_standard_deploy)
      else
        run_async_jobs
      end
    end

    def tag_staging_exists? # check exists task from capistrano-gitflow
      @jobs.find(&:gitflow).present?
    end

    def stages_key
      'STAGES'
    end

    def fetch_multi_stages
      custom_stages = @argv[stages_key].blank? ? '' : @argv[stages_key]
      custom_stages = strip_characters_from_string(custom_stages).split(',').compact if custom_stages.present?
      custom_stages = custom_stages.present? ? custom_stages : [@default_stage]
      custom_stages
    end

    def wants_deploy_production?
      (!custom_command? && @stage == 'production') || (custom_command? && fetch_multi_stages.include?('production'))
    end

    def can_tag_staging?
      wants_deploy_production? && fetch_multi_stages.include?('staging')
    end

    def deploy_app(options = {})
      options = options.stringify_keys
      call_task_deploy_app({
        app: options['app'],
        action: options['action']
      }.reverse_merge(options))
    end

    def get_app_additional_env_options(app, app_message)
      app_name = (app.is_a?(Hash) && app[:app].present?) ? app[:app].camelcase : app
      app_name = app_name.present? ? app_name : 'current application'
      message = "Please write additional ENV options for #{app_name} for #{app_message}"
      app_additional_env_options = ask_confirm(message, nil)
      fetch_app_additional_env_options(app_additional_env_options)
    end

    def run
      options = {}
      if custom_command?
        options = verify_options_custom_command(options)
        run_custom_command(options)
      else
        collect_jobs(options)
      end
      process_jobs
    end

    def boxes_key
      'BOX'
    end

    def call_task_deploy_app(options = {})
      options = options.stringify_keys
      main_box_name = @argv[boxes_key].blank? ? '' : @argv[boxes_key]
      boxes = strip_characters_from_string(main_box_name).split(',').compact
      stage = options.fetch('stage', @default_stage)
      if configuration.development_stages.include?(stage) && boxes.present?
        execute_on_multiple_boxes(boxes, options)
      else
        prepare_job(options)
      end
    end

    def run_async_jobs
      return unless @jobs.present?
      @jobs.pmap do |job|
        @manager.async.delegate_job(job)
      end
      unless can_tag_staging? && tag_staging_exists?
        until @manager.registration_complete
          sleep(0.1) # keep current thread alive
        end
        return unless @manager.registration_complete
        @manager.async.process_jobs
      end
      wait_jobs_termination
    end

    def wait_jobs_termination
      return if configuration.multi_secvential.to_s.downcase == 'true'
      result = @condition.wait
      return unless result.present?
      @manager.terminate
      #terminate
    end

    def prepare_job(options)
      options = options.stringify_keys
      return raise_invalid_job_config if !job_stage_valid?(options)
      app = options.fetch('app', '')
      box = options['env_options'][boxes_key]
      message = box.present? ? "BOX #{box}:" : "stage #{options['stage']}:"
      env_opts = get_app_additional_env_options(app, message)

      options['env_options'] = options['env_options'].reverse_merge(env_opts)

      env_options = options['env_options']
      job_env_options = custom_command? ? env_options.except(action_key) : env_options
      job = CapistranoMulticonfigParallel::Job.new(self, options.merge(
                                                                    action: custom_command? && env_options[action_key].present? ? env_options[action_key] : options['action'],
                                                                    env_options: job_env_options,
                                                                    path: options.fetch('path', nil)

      ))
      @jobs << job unless job_can_tag_staging?(job)
    end

    def job_can_tag_staging?(job)
      can_tag_staging? && job.stage == 'production' && job.gitflow.present?
    end

    def job_path(options)
      options.fetch("path", nil).present? ? options["path"] : detect_root
    end

    def job_stage_valid?(options)
      stages(job_path(options)).include?(job_stage(options))
    end

    def job_stage(options)
      multi_apps?(job_path(options)) && options.fetch('app', nil).present? ? "#{options['app']}:#{options['stage']}" : "#{options['stage']}"
    end


    def prepare_options(options)
      options = options.stringify_keys
      options['app'] = options.fetch('app', @application.to_s.clone)
      options['action'] = options.fetch('action', @name.to_s.clone)
      options['stage'] = options.fetch('stage', @stage.to_s.clone)
      options['env_options'] = options.fetch('env_options', @argv.clone)
      options['task_arguments'] = options.fetch('task_arguments', @args.clone)
      options
    end

    def fetch_app_additional_env_options(variable)
      options = {}
      return options if variable.blank?
      env_options = strip_characters_from_string(variable)
      env_options = env_options.split(' ')
      options = multi_fetch_argv(env_options)
      options.stringify_keys!
      options
    end

    def execute_on_multiple_boxes(boxes, options)
      boxes.each do |box_name|
        options['env_options'][boxes_key] = box_name
        prepare_job(options)
      end
    end
  end
end
