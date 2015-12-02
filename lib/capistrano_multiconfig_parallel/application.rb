module CapistranoMulticonfigParallel
  # finds app dependencies, shows menu and delegates jobs to celluloid manager
  # rubocop:disable ClassLength
  class Application
    include Celluloid
    include Celluloid::Logger

    attr_accessor :stages,:stage_apps, :top_level_tasks, :jobs, :branch_backup, :condition, :manager, :dependency_tracker, :application, :stage, :name, :args, :argv, :default_stage

    def initialize
      @stages = fetch_stages
      @stage_apps =  multi_apps? ? @stages.map { |stage| stage.split(':').reverse[1] }.uniq : []
      collect_command_line_tasks(CapistranoMulticonfigParallel.original_args)
      @jobs = []
      CapistranoMulticonfigParallel.configuration_valid?(@stages)
    end


    def start
      verify_app_dependencies(@stages) if multi_apps? && configuration.application_dependencies.present?
      check_before_starting
      initialize_data
      run
    end

    def verify_app_dependencies(stages)
      wrong = configuration.application_dependencies.find do |hash|
        !@stage_apps.include?(hash[:app]) || (hash[:dependencies].present? && hash[:dependencies].find { |val| !@stage_apps.include?(val) })
      end
      raise ArgumentError,"Invalid configuration for #{wrong.inspect}".red if wrong.present?
    end


    def fetch_stages
      fetch_stages_paths do |paths|
        paths.reject! { |path| check_stage_path(paths, path) }.sort
      end
    end

    def check_stage_path(paths, path)
      paths.any? { |another| another != path && another.start_with?(path + ':') }
    end

    def stages_paths
      stages_root = 'config/deploy'
      Dir["#{stages_root}/**/*.rb"].map do |file|
        file.slice(stages_root.size + 1..-4).tr('/', ':')
      end
    end

    def fetch_stages_paths
      stages_paths.tap { |paths| yield paths if block_given? }
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
        deploy_app(options.merge('app' => app))
      end
    end

    def backup_the_branch
      return if custom_command? || @argv['BRANCH'].blank?
      @branch_backup = @argv['BRANCH'].to_s
      @argv['BRANCH'] = nil
    end

    def can_start?
      @top_level_tasks.size >= 1 && (@stages.include?(@top_level_tasks.first) || custom_command?) && @argv[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
    end

    def custom_command?
      if multi_apps?
        !@stages.include?(@top_level_tasks.first) && custom_commands.values.include?(@top_level_tasks.first)
      else
        !@stages.include?(@top_level_tasks.second) && @stages.include?(@top_level_tasks.first) && custom_commands.values.include?(@top_level_tasks.second)
      end
    end

    def custom_commands
      key = multi_apps? ? CapistranoMulticonfigParallel::MULTI_KEY : CapistranoMulticonfigParallel::SINGLE_KEY
      CapistranoMulticonfigParallel::CUSTOM_COMMANDS[key]
    end

    def multi_apps?
      @stages.find { |stage| stage.include?(':') }.present?
    end

    def configuration
      CapistranoMulticonfigParallel.configuration
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

    def parse_task_string(string) # :nodoc:
      /^([^\[]+)(?:\[(.*)\])$/ =~ string.to_s

      name           = Regexp.last_match(1)
      remaining_args = Regexp.last_match(2)

      return string, [] unless name
      return name,   [] if     remaining_args.empty?

      args = []

      loop do
        /((?:[^\\,]|\\.)*?)\s*(?:,\s*(.*))?$/ =~ remaining_args

        remaining_args = Regexp.last_match(2)
        args << Regexp.last_match(1).gsub(/\\(.)/, '\1')
        break if   remaining_args.blank?
      end

      [name, args]
    end

    def verify_options_custom_command(options)
      options[:action] = @argv['ACTION'].present? ? @argv['ACTION'] : 'deploy'
      options
    end

    def check_before_starting
      CapistranoMulticonfigParallel.enable_logging
      @dependency_tracker = CapistranoMulticonfigParallel::DependencyTracker.new(Actor.current)
      @default_stage = CapistranoMulticonfigParallel.configuration.development_stages.present? ? CapistranoMulticonfigParallel.configuration.development_stages.first : 'development'
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
    rescue => e
      CapistranoMulticonfigParallel.log_message(e)
    end

    def process_jobs
      return unless @jobs.present?
      FileUtils.rm Dir["#{CapistranoMulticonfigParallel.log_directory}/worker_*.log"]
      if configuration.multi_secvential.to_s.downcase == 'true'
        @jobs.each { |job| CapistranoMulticonfigParallel::StandardDeploy.new(job) }
      else
        run_async_jobs
      end
    end

    def tag_staging_exists? # check exists task from capistrano-gitflow
      CapistranoMulticonfigParallel.find_loaded_gem('capistrano-gitflow').present?
    end


    def fetch_multi_stages
      custom_stages = @argv['STAGES'].blank? ? '' : @argv['STAGES']
      custom_stages = parse_inputted_value('value' => custom_stages).split(',').compact if custom_stages.present?
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
      app_additional_env_options = CapistranoMulticonfigParallel.ask_confirm(message, nil)
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
      return if configuration.multi_secvential.to_s.downcase == 'true'
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
        id: SecureRandom.random_number(500),
        app: app,
        env: options['stage'],
        action: custom_command? && env_options['ACTION'].present? ? env_options['ACTION'] : options['action'],
        task_arguments: options['task_arguments'],
        env_options: job_env_options
      }
      @jobs << job.stringify_keys
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
      value = options['value'].present? ? options['value'] : nil
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

    def fetch_app_additional_env_options(variable)
      options = {}
      return options if variable.blank?
      env_options = parse_inputted_value('value' => variable)
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
