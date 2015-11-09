require_relative './standard_deploy'
require_relative '../celluloid/celluloid_manager'
module CapistranoMulticonfigParallel
  # finds app dependencies, shows menu and delegates jobs to celluloid manager
  # rubocop:disable ClassLength
  class BaseManager
    include Celluloid
    include Celluloid::Logger

    attr_accessor :condition, :manager, :deps, :application, :stage, :name, :args, :argv, :jobs, :job_registered_condition, :default_stage, :original_argv

    def initialize(cap_app, top_level_tasks, stages)
      @cap_app = cap_app
      @top_level_tasks = top_level_tasks
      @stages = stages
      @jobs = []
      CapistranoMulticonfigParallel.enable_logging
    end

    def can_start?
      @top_level_tasks.size > 1 && (stages.include?(@top_level_tasks.first) || custom_command?) && ENV[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
    end

    def custom_command?
      @top_level_tasks.first == 'ensure_stage' && !stages.include?(@top_level_tasks.second) && !stages.include?(@top_level_tasks.first) && custom_commands.values.include?(@top_level_tasks.second)
    end

    def custom_commands
      key = multi_apps? ? CapistranoMulticonfigParallel::MULTI_KEY : CapistranoMulticonfigParallel::SINGLE_KEY
      CapistranoMulticonfigParallel::CUSTOM_COMMANDS[key]
    end

    def executes_deploy_stages?
      @name == custom_commands[:stages]
    end

    def multi_apps?
      @cap_app.multi_apps?
    end

    def configuration
      CapistranoMulticonfigParallel.configuration
    end

    def start(&block)
      check_before_starting
      initialize_data
      block.call if block_given?
      run
    end

    def initialize_data
      @application = custom_command? ? nil : @top_level_tasks.first.split(':').reverse[1]
      @stage = custom_command? ? nil : @top_level_tasks.first.split(':').reverse[0]
      @stage = @stage.present? ? @stage : @default_stage
      @name, @args = @cap_app.parse_task_string(@top_level_tasks.second)
      @argv = @cap_app.handle_options.delete_if { |arg| arg == @stage || arg == @name || arg == @top_level_tasks.first }
      @argv = multi_fetch_argv(@argv)
      @original_argv = @argv.clone
    end

    def verify_options_custom_command(options)
      options[:action] = @argv['ACTION'].present? ? @argv['ACTION'] : 'deploy'
      options
    end

    def check_before_starting
      CapistranoMulticonfigParallel.configuration_valid?
      @default_stage = CapistranoMulticonfigParallel.configuration.development_stages.present? ? CapistranoMulticonfigParallel.configuration.development_stages.first : 'development'
      @condition = Celluloid::Condition.new
      @manager = CapistranoMulticonfigParallel::CelluloidManager.new(Actor.current)
    end

    def collect_jobs(options = {}, &block)
      options = prepare_options(options)
      block.call(options) if block_given?
    rescue => e
      raise [e, e.backtrace].inspect
    end

    def process_jobs
      return unless @jobs.present?
      if CapistranoMulticonfigParallel.execute_in_sequence
        @jobs.each { |job| CapistranoMulticonfigParallel::StandardDeploy.execute_standard_deploy(job) }
      else
        run_async_jobs
      end
    end

    def tag_staging_exists? # check exists task from capistrano-gitflow
      check_giflow_tasks(
        CapistranoMulticonfigParallel::GITFLOW_TAG_STAGING_TASK,
        CapistranoMulticonfigParallel::GITFLOW_CALCULATE_TAG_TASK,
        CapistranoMulticonfigParallel::GITFLOW_VERIFY_UPTODATE_TASK
      )
    rescue
      return false
    end

    def check_giflow_tasks(*tasks)
      tasks.all? { |t| Rake::Task[t].present? }
    end

    def fetch_multi_stages
      stages = @argv['STAGES'].blank? ? '' : @argv['STAGES']
      stages = parse_inputted_value('value' => stages).split(',').compact if stages.present?
      stages = stages.present? ? stages : [@default_stage]
      stages
    end

    def wants_deploy_production?
      (!custom_command? && @stage == 'production') || (custom_command? && fetch_multi_stages.include?('production'))
    end

    def can_tag_staging?
      using_git? && wants_deploy_production? && tag_staging_exists? && fetch_multi_stages.include?('staging')
    end

    def check_multi_stages(stages)
      can_tag_staging? ? stages.reject { |u| u == 'production' } : stages
    end

    def deploy_app(options = {})
      options = options.stringify_keys
      app = options['app'].is_a?(Hash) ? options['app'] : { 'app' => options['app'] }
      branch = @branch_backup.present? ? @branch_backup : @argv['BRANCH'].to_s
      call_task_deploy_app({
        branch: branch,
        app: app,
        action: options['action']
      }.reverse_merge(options))
    end

    def get_app_additional_env_options(app, app_message)
      app_name = (app.is_a?(Hash) && app[:app].present?) ? app[:app].camelcase : app
      app_name = app_name.present? ? app_name : 'current application'
      message = "Please write additional ENV options for #{app_name} for #{app_message}"
      set :app_additional_env_options, CapistranoMulticonfigParallel.ask_confirm(message, nil)
      fetch_app_additional_env_options
    end

    def worker_environments
      @jobs.map { |job| job['env'] }
    end

    def confirmation_applies_to_all_workers?
      CapistranoMulticonfigParallel.configuration.apply_stage_confirmation.all? { |e| worker_environments.include?(e) }
    end

  private

    def call_task_deploy_app(options = {})
      options = options.stringify_keys
      main_box_name = @argv['BOX'].blank? ? '' : @argv['BOX']
      stage = options.fetch('stage', @default_stage)
      if CapistranoMulticonfigParallel.configuration.development_stages.include?(stage) && main_box_name.present? && /^[a-z0-9,]+/.match(main_box_name)
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
      return if CapistranoMulticonfigParallel.execute_in_sequence
      result = @condition.wait
      return unless result.present?
      @manager.terminate
      terminate
    end

    def prepare_job(options)
      options = options.stringify_keys
      branch_name = options.fetch('branch', {})
      app = options.fetch('app', {})
      app = app.fetch('app', '')
      box = options['env_options']['BOX']
      message = box.present? ? "BOX #{box}:" : "stage #{options['stage']}:"
      env_opts = get_app_additional_env_options(app, message)

      options['env_options'] = options['env_options'].reverse_merge(env_opts)

      env_options = branch_name.present? ? { 'BRANCH' => branch_name }.merge(options['env_options']) : options['env_options']
      job_env_options = custom_command? && env_options['ACTION'].present? ? env_options.except('ACTION') : env_options

      job = {
        app: app,
        env: options['stage'],
        action: custom_command? && env_options['ACTION'].present? ? env_options['ACTION'] : options['action'],
        task_arguments: options['task_arguments'],
        env_options: job_env_options
      }
      job = job.stringify_keys
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

    def parse_inputted_value(options = {})
      options = options.stringify_keys
      value = options['value'].present? ? options['value'] : fetch(options.fetch('key', :app_branch_name))
      if value.present?
        branch = value.gsub("\r\n", '')
        branch = branch.delete("\n") if branch.present?
        branch = branch.gsub(/\s+/, ' ') if branch.present?
        branch = branch.strip if branch.present?
        return branch
      else
        return ''
      end
    end

    def using_git?
      fetch(:scm, :git).to_sym == :git
    end

    def fetch_app_additional_env_options
      options = {}
      return options if fetch(:app_additional_env_options).blank?
      env_options = parse_inputted_value('key' => :app_additional_env_options)
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
      boxes = parse_inputted_value('value' => main_box_name).split(',').compact
      boxes.each do |box_name|
        options['env_options']['BOX'] = box_name
        prepare_job(options)
      end
    end
  end
end
