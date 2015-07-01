require_relative './standard_deploy'
module CapistranoMulticonfigParallel
  # finds app dependencies, shows menu and delegates jobs to celluloid manager
  # rubocop:disable ClassLength
  class BaseManager
    include Celluloid
    include Celluloid::Logger

    attr_accessor :condition, :manager, :deps, :application, :stage, :name, :args, :argv, :jobs, :job_registered_condition, :default_stage

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

    def start(&block)
      check_before_starting
      @application = custom_command? ? nil : @top_level_tasks.first.split(':').reverse[1]
      @stage = custom_command? ? nil : @top_level_tasks.first.split(':').reverse[0]
      @name, @args = @cap_app.parse_task_string(@top_level_tasks.second)
      @argv = @cap_app.handle_options.delete_if { |arg| arg == @stage || arg == @name || arg == @top_level_tasks.first }
      @argv = multi_fetch_argv(@argv)
      block.call if block_given?
      run
    end

    def check_before_starting
      CapistranoMulticonfigParallel.configuration_valid?
      CapistranoMulticonfigParallel.verify_app_dependencies(@stages) if   CapistranoMulticonfigParallel.configuration.present? && CapistranoMulticonfigParallel.configuration.track_dependencies.to_s.downcase == 'true'
      @condition = Celluloid::Condition.new
      @manager = CapistranoMulticonfigParallel::CelluloidManager.new(Actor.current)
      if CapistranoMulticonfigParallel::CelluloidManager.debug_enabled == true
        Celluloid.logger =CapistranoMulticonfigParallel.logger
        Celluloid.task_class = Celluloid::TaskThread
      end
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

    def fetch_multi_stages
      stages = @argv['STAGES'].blank? ? '' : @argv['STAGES']
      stages = parse_inputted_value(value: stages).split(',').compact if stages.present?
      stages
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
      return if @jobs.blank? || CapistranoMulticonfigParallel.execute_in_sequence
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

      options['env_options'] = options['env_options'].reverse_merge(env_opts.except('BOX'))
      
      env_options = branch_name.present? ?  { 'BRANCH' => branch_name }.merge(options['env_options']) : options['env_options']

      job = {
        app: app,
        env: options['stage'],
        action: options['action'],
        task_arguments: options['task_arguments'],
        env_options: env_options
      }

      @jobs << job
    end

    def prepare_options(options)
      @default_stage = CapistranoMulticonfigParallel.configuration.development_stages.present? ? CapistranoMulticonfigParallel.configuration.development_stages.first : 'development'
      @stage = @stage.present? ? @stage : @default_stage
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
        branch = branch.gsub("\n", '') if branch.present?
        branch = branch.gsub(/\s+/, ' ') if branch.present?
        branch = branch.strip if branch.present?
        return branch
      else
        return ''
      end
    end

    

    def get_app_additional_env_options(app, app_message)
      app_name = (app.is_a?(Hash) && app[:app].present?) ? app[:app].camelcase : app
      app_name = app_name.present? ? app_name : 'current application'
      message = "Please write additional ENV options for #{app_name} for #{app_message}"
      set :app_additional_env_options, CapistranoMulticonfigParallel.ask_confirm(message, nil)
      fetch_app_additional_env_options
    end

    def fetch_app_additional_env_options
      options = {}
      return options if fetch(:app_additional_env_options).blank?
      env_options = parse_inputted_value(key: :app_additional_env_options)
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
      boxes = parse_inputted_value(value: main_box_name).split(',').compact
      boxes.each do |box_name|
        options['env_options']['BOX'] = box_name
        prepare_job(options)
      end
    end
  end
end
