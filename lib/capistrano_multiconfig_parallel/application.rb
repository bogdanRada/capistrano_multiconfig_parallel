module CapistranoMulticonfigParallel
  # finds app dependencies, shows menu and delegates jobs to celluloid manager
  # rubocop:disable ClassLength
  class Application
    include Celluloid
    include Celluloid::Logger
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :stages, :stage_apps, :top_level_tasks, :jobs, :branch_backup, :condition, :manager, :dependency_tracker, :application, :stage, :name, :args, :argv, :default_stage

    def initialize
      Celluloid.boot
      @stages = fetch_stages
      @stage_apps = multi_apps? ? @stages.map { |stage| stage.split(':').reverse[1] }.uniq : []
      collect_command_line_tasks(CapistranoMulticonfigParallel.original_args)
      @jobs = []
    end

    def start
      verify_app_dependencies if multi_apps? && app_configuration.application_dependencies.present?
      check_before_starting
      initialize_data
      run
    end

    def verify_app_dependencies
      wrong = app_configuration.application_dependencies.find do |hash|
        !@stage_apps.include?(hash[:app]) || (hash[:dependencies].present? && hash[:dependencies].find { |val| !@stage_apps.include?(val) })
      end
      raise ArgumentError, "Invalid configuration for #{wrong.inspect}".red if wrong.present?
    end

    def run_custom_command(options)
      custom_stages = fetch_multi_stages
      return if custom_stages.blank?
      custom_stages = check_multi_stages(custom_stages)
      custom_stages.each do |stage|
        collect_jobs(options.merge('stage' => stage))
      end
    end

    def deploy_multiple_apps(applications, options)
      options = options.stringify_keys
      return unless applications.present?
      applications.each do |app|
        deploy_app(options.merge('app' => app['app']))
      end
    end

    def backup_the_branch
      return if custom_command? || @argv['BRANCH'].blank?
      @branch_backup = @argv['BRANCH'].to_s
      @argv['BRANCH'] = nil
    end

    def custom_command?
      if multi_apps?
        !@stages.include?(@top_level_tasks.first) && custom_commands.include?(@top_level_tasks.first)
      else
        !@stages.include?(@top_level_tasks.second) && @stages.include?(@top_level_tasks.first) && custom_commands.include?(@top_level_tasks.second)
      end
    end

    def multi_apps?
      @stages.find { |stage| stage.include?(':') }.present?
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

    def verify_options_custom_command(options)
      options[:action] = @argv['ACTION'].present? ? @argv['ACTION'] : 'deploy'
      options
    end

    def check_before_starting
      CapistranoMulticonfigParallel.enable_logging
      @dependency_tracker = CapistranoMulticonfigParallel::DependencyTracker.new(Actor.current)
      @default_stage = app_configuration.development_stages.present? ? app_configuration.development_stages.first : 'development'
      @condition = Celluloid::Condition.new
      @manager = CapistranoMulticonfigParallel::CelluloidManager.new(Actor.current)
    end

    def collect_jobs(options = {}, &_block)
      options = prepare_options(options)
      options = options.stringify_keys
      apps = @dependency_tracker.fetch_apps_needed_for_deployment(options['app'], options['action'])
      backup_the_branch if multi_apps?
      deploy_multiple_apps(apps, options)
      deploy_app(options) if !custom_command? || !multi_apps?
    end

    def process_jobs
      return unless @jobs.present?
      FileUtils.rm Dir["#{log_directory}/worker_*.log"]
      if app_configuration.multi_secvential.to_s.downcase == 'true'
        @jobs.each(&:execute_standard_deploy)
      else
        run_async_jobs
      end
    end

    def tag_staging_exists? # check exists task from capistrano-gitflow
      find_loaded_gem('capistrano-gitflow').present?
    end

    def fetch_multi_stages
      custom_stages = @argv['STAGES'].blank? ? '' : @argv['STAGES']
      custom_stages = strip_characters_from_string(custom_stages).split(',').compact if custom_stages.present?
      custom_stages = custom_stages.present? ? custom_stages : [@default_stage]
      custom_stages
    end

    def wants_deploy_production?
      (!custom_command? && @stage == 'production') || (custom_command? && fetch_multi_stages.include?('production'))
    end

    def can_tag_staging?
      wants_deploy_production? && tag_staging_exists? && fetch_multi_stages.include?('staging')
    end

    def check_multi_stages(custom_stages)
      can_tag_staging? ? custom_stages.reject { |u| u == 'production' } : custom_stages
    end

    def deploy_app(options = {})
      options = options.stringify_keys
      branch = @branch_backup.present? ? @branch_backup : @argv['BRANCH'].to_s
      call_task_deploy_app({
        branch: branch,
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

    def worker_environments
      @jobs.map { |job| job['env'] }
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

    def call_task_deploy_app(options = {})
      options = options.stringify_keys
      main_box_name = @argv['BOX'].blank? ? '' : @argv['BOX']
      stage = options.fetch('stage', @default_stage)
      if app_configuration.development_stages.include?(stage) && main_box_name.present? && /^[a-z0-9,]+/.match(main_box_name)
        execute_on_multiple_boxes(main_box_name, options)
      else
        prepare_job(options)
      end
    end

    def run_async_jobs
      return unless @jobs.present?
      @jobs.pmap do |job|
        @manager.async.delegate(job)
      end
      until @manager.registration_complete
        sleep(0.1) # keep current thread alive
      end
      return unless @manager.registration_complete
      @manager.async.process_jobs
      wait_jobs_termination
    end

    def wait_jobs_termination
      return if app_configuration.multi_secvential.to_s.downcase == 'true'
      result = @condition.wait
      return unless result.present?
      @manager.terminate
      terminate
    end

    # rubocop:disable CyclomaticComplexity
    def prepare_job(options)
      options = options.stringify_keys
      branch_name = options.fetch('branch', {})
      app = options.fetch('app', '')
      box = options['env_options']['BOX']
      message = box.present? ? "BOX #{box}:" : "stage #{options['stage']}:"
      env_opts = get_app_additional_env_options(app, message)

      options['env_options'] = options['env_options'].reverse_merge(env_opts)

      env_options = branch_name.present? ? { 'BRANCH' => branch_name }.merge(options['env_options']) : options['env_options']
      job_env_options = custom_command? && env_options['ACTION'].present? ? env_options.except('ACTION') : env_options

      job = CapistranoMulticonfigParallel::Job.new(options.merge(
                                                     action: custom_command? && env_options['ACTION'].present? ? env_options['ACTION'] : options['action'],
                                                     env_options: job_env_options
      ))
      @jobs << job
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

    def multi_fetch_argv(args)
      options = {}
      args.each do |arg|
        if arg =~ /^(\w+)=(.*)$/m
          options[Regexp.last_match(1)] = Regexp.last_match(2)
        end
      end
      options
    end

    def execute_on_multiple_boxes(main_box_name, options)
      boxes = strip_characters_from_string(main_box_name).split(',').compact
      boxes.each do |box_name|
        options['env_options']['BOX'] = box_name
        prepare_job(options)
      end
    end
  end
end
