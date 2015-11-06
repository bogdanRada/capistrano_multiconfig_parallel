require_relative './child_process'
require_relative './state_machine'
module CapistranoMulticonfigParallel
  # rubocop:disable ClassLength
  # worker that will spawn a child process in order to execute a capistrano job and monitor that process
  #
  # @!attribute job
  #   @return [Hash] options used for executing capistrano task
  #   @option options [String] :id The id of the job ( will ge automatically generated by CapistranoMulticonfigParallel::CelluloidManager when delegating job)
  #   @option options [String] :app The application name that will be deployed
  #   @option options [String] :env The stage used for that application
  #   @option options [String] :action The action that this action will be doing (deploy, or other task)
  #   @option options [Hash] :env_options  options that are available  in the environment variable ENV when this task is going to be executed
  #   @option options [Array] :task_arguments arguments to the task
  #
  # @!attribute manager
  #   @return [CapistranoMulticonfigParallel::CelluloidManager] the instance of the manager that delegated the job to this worker
  #
  class CelluloidWorker
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Logger
    class TaskFailed < StandardError; end

    attr_accessor :job, :manager, :job_id, :app_name, :env_name, :action_name, :env_options, :machine, :client, :task_argv, :execute_deploy, :executed_dry_run,
                  :rake_tasks, :current_task_number, # tracking tasks
                  :successfull_subscription, :subscription_channel, :publisher_channel, # for subscriptions and publishing events
                  :job_termination_condition, :worker_state, :executing_dry_run, :job_argv, :dry_run_tasks

    def work(job, manager)
      @job = job
      @worker_state = 'started'
      @executing_dry_run = nil
      @manager = manager
      @job_confirmation_conditions = []
      process_job(job) if job.present?
      debug("worker #{@job_id} received #{job.inspect}") if debug_enabled?
      @subscription_channel = "worker_#{@job_id}"
      @machine = CapistranoMulticonfigParallel::StateMachine.new(job, Actor.current)
      manager.register_worker_for_job(job, Actor.current)
    end

    def debug_enabled?
      @manager.class.debug_enabled?
    end

    def start_task
      @manager.setup_worker_conditions(Actor.current)
      debug("exec worker #{@job_id} starts task with #{@job.inspect}") if debug_enabled?
      @client = CelluloidPubsub::Client.connect(actor: Actor.current, enable_debug: @manager.class.debug_websocket?, :channel => subscription_channel)
    end

    def publish_rake_event(data)
      @client.publish(rake_actor_id(data), data)
    end


    def rake_actor_id(data)
      data['action'].present? && data['action'] == 'count' ? "rake_worker_#{@job_id}_count" : "rake_worker_#{@job_id}"
    end

    def on_message(message)
      debug("worker #{@job_id} received:  #{message.inspect}") if debug_enabled?
      if @client.succesfull_subscription?(message)
        @successfull_subscription = true
        execute_after_succesfull_subscription
      else
        handle_subscription(message)
      end
    end

    def execute_after_succesfull_subscription
        async.execute_deploy
    end

    def rake_tasks
      @rake_tasks ||= []
    end

    def dry_run_tasks
         @dry_run_tasks ||= []
    end

    def cd_working_directory
      "cd #{CapistranoMulticonfigParallel.detect_root}"
    end

    def generate_command
      <<-CMD
           #{cd_working_directory} && RAILS_ENV=#{@env_name} bundle exec multi_cap #{@task_argv.join(' ')}
      CMD
    end

    def execute_deploy
      @execute_deploy = true
      debug("invocation chain #{@job_id} is : #{@rake_tasks.inspect}") if debug_enabled?
      check_child_proces
      setup_task_arguments
      debug("worker #{@job_id} executes: #{generate_command}") if debug_enabled?
      @child_process.async.work(generate_command, actor: Actor.current, silent: true)
      @manager.wait_task_confirmations_worker(Actor.current)
    end

    def check_child_proces
      if !defined?(@child_process) || @child_process.nil?
        @child_process = CapistranoMulticonfigParallel::ChildProcess.new
        Actor.current.link @child_process
      else
        @client.unsubscribe("rake_worker_#{@job_id}_count")
        @child_process.exit_status = nil
      end
    end

    def on_close(code, reason)
      debug("worker #{@job_id} websocket connection closed: #{code.inspect}, #{reason.inspect}") if debug_enabled?
    end

    def check_gitflow
      return if dry_running? ||  @env_name != 'staging' || !@manager.can_tag_staging? || !executed_task?(CapistranoMulticonfigParallel::GITFLOW_TAG_STAGING_TASK)
      @manager.dispatch_new_job(@job.merge('env' => 'production'))
    end

    def handle_subscription(message)
        @executing_dry_run = message['action'] == 'count' ? true : false
        @manager.jobs[@job_id]['job_argv'] = @job_argv
      if message_is_about_a_task?(message)
        check_gitflow
        save_tasks_to_be_executed(message)
        update_machine_state(message['task']) # if message['action'] == 'invoke'
        debug("worker #{@job_id} state is #{@machine.state}") if debug_enabled?
        task_approval(message)
      elsif message_is_for_stdout?(message)
       result =   Celluloid::Actor[:terminal_server].show_confirmation(message['question'],message['default'])
       publish_rake_event(message.merge('action' => "stdin",'result' => result, "client_action" => "stdin"))
      else
        debug("worker #{@job_id} could not handle  #{message}") if debug_enabled?
      end
    end

      def message_is_for_stdout?(message)
      message.present? && message.is_a?(Hash) && message['action'].present? && message['job_id'].present? && message['action'] == 'stdout'
    end

    def message_is_about_a_task?(message)
      message.present? && message.is_a?(Hash) && message['action'].present? && message['job_id'].present? && message['task'].present?
    end

    def executed_task?(task)
      rake_tasks.present? && rake_tasks.index(task.to_s).present?
    end

    def task_approval(message)
      if @manager.apply_confirmations? && CapistranoMulticonfigParallel.configuration.task_confirmations.include?(message['task']) && message['action'] == 'invoke'
        task_confirmation = @manager.job_to_condition[@job_id][message['task']]
        task_confirmation[:status] = 'confirmed'
        task_confirmation[:condition].signal(message['task'])
      else
        publish_rake_event(message.merge('approved' => 'yes'))
      end
    end

    def save_tasks_to_be_executed(message)
      debug("worler #{@job_id} current invocation chain : #{rake_tasks.inspect}") if debug_enabled?
      rake_tasks << message['task'] if rake_tasks.last != message['task']
      dry_run_tasks << message['task'] if dry_running? &&  dry_run_tasks.last != message['task']
    end

    def update_machine_state(name)
      debug("worker #{@job_id} triest to transition from #{@machine.state} to  #{name}") if debug_enabled?
      @machine.transitions.on(name.to_s, @machine.state => name.to_s)
      @machine.go_to_transition(name.to_s)
      raise(CapistranoMulticonfigParallel::CelluloidWorker::TaskFailed, "task #{@action} failed ") if name == 'deploy:failed' # force worker to rollback
    end

    def setup_command_line(*options)
      @task_argv = []
      options.each do |option|
        @task_argv << option
      end
      @task_argv
    end

    def dry_run_command
      '--dry-run'
    end

    def dry_running?
      @task_argv.include?(dry_run_command) == true
    end

    def worker_stage
      @app_name.present? ? "#{@app_name}:#{@env_name}" : "#{@env_name}"
    end

    def worker_action
       "#{@action_name}[#{@task_arguments.join(',')}]"
    end

    def setup_task_arguments(*args)
      #   stage = "#{@app_name}:#{@env_name} #{@action_name}"
      array_options = []
      @env_options.each do |key, value|
        array_options << "#{key}=#{value}" if value.present?
        end
      array_options << '--trace' if debug_enabled?
      args.each do |arg|
        array_options << arg
      end
      @job_argv= array_options.clone
      array_options.unshift("#{worker_action}")
       array_options.unshift("#{worker_stage}")
      setup_command_line(*array_options)
    end

    def send_msg(channel, message = nil)
      publish channel, message.present? && message.is_a?(Hash) ? { job_id: @job_id }.merge(message) : { job_id: @job_id, time: Time.now }
    end

    def process_job(job)
      processed_job = @manager.process_job(job)
      @job_id = processed_job['job_id']
      @app_name = processed_job['app_name']
      @env_name = processed_job['env_name']
      @action_name = processed_job['action_name']
      @env_options = processed_job['env_options']
      @task_arguments = processed_job['task_arguments']
    end

    def crashed?
      @action_name == 'deploy:rollback' || @action_name == 'deploy:failed' || @manager.job_failed?(@job)
    end

    def finish_worker
      @manager.mark_completed_remaining_tasks(Actor.current)
      @manager.jobs[@job_id]['worker_action'] = 'finished'
      @manager.workers_terminated.signal('completed')  if @manager.all_workers_finished?
    end

    def worker_finshed?
       @manager.jobs[@job_id]['worker_action'] == 'finished'
    end

    def notify_finished(exit_status)
      if exit_status.exitstatus != 0
        debug("worker #{job_id} tries to terminate") if debug_enabled?
        raise(CapistranoMulticonfigParallel::CelluloidWorker::TaskFailed, "task  failed with exit status #{exit_status.inspect} ")  # force worker to rollback
      else
        update_machine_state('FINISHED')
        debug("worker #{job_id} notifies manager has finished") if debug_enabled?
        finish_worker
      end
    end
  end
end
