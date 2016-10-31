# frozen_string_literal: true
require_relative '../helpers/base_actor_helper'
require_relative '../classes/child_process_status'
require_relative './state_machine'
require_relative './process_runner'
module CapistranoMulticonfigParallel
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
    include CapistranoMulticonfigParallel::BaseActorHelper

    ATTRIBUTE_LIST = [
      :job, :manager, :job_id, :app_name, :env_name, :action_name, :env_options, :machine, :socket_connection, :task_argv,
      :rake_tasks, :current_task_number, # tracking tasks
      :successfull_subscription, :subscription_channel, :publisher_channel, # for subscriptions and publishing events
      :job_termination_condition, :invocation_chain, :filename, :worker_log, :exit_status, :old_job
    ].freeze

    attr_reader *CapistranoMulticonfigParallel::CelluloidWorker::ATTRIBUTE_LIST
    attr_accessor *CapistranoMulticonfigParallel::CelluloidWorker::ATTRIBUTE_LIST

    def initialize(*args)
    end

    def work(job, manager, old_job)
      @job = job
      @old_job = old_job
      @job_id = job.id
      @worker_state = job.status
      @manager = manager
      @job_confirmation_conditions = []
      log_to_file("worker #{@job_id} received #{job.inspect} and #{old_job.inspect}")
      @subscription_channel = "#{CapistranoSentinel::RequestHooks::PUBLISHER_PREFIX}#{@job_id}"
      @machine = CapistranoMulticonfigParallel::StateMachine.new(@job, Actor.current)
      @manager.setup_worker_conditions(@job)
      manager.register_worker_for_job(job, Actor.current)
    end

    def worker_state
      if !job.status.to_s.casecmp('dead').zero? && Actor.current.alive?
        @machine.state.to_s.green
      else
        job.status = 'dead'
        job.status.upcase.red
      end
    end

    def start_task
      log_to_file("exec worker #{@job_id} starts task and subscribes to #{@subscription_channel}")
      if @old_job.present? && @old_job.is_a?(CapistranoMulticonfigParallel::Job)
        @old_job.new_jobs_dispatched << @job.id
      end
      @socket_connection = CelluloidPubsub::Client.new(actor: Actor.current, enable_debug: debug_websocket?, channel: subscription_channel, log_file_path: websocket_config.fetch('log_file_path', nil))
    end

    def publish_rake_event(data)
      log_to_file("worker #{@job_id} rties to publish into channel #{CapistranoSentinel::RequestHooks::SUBSCRIPTION_PREFIX}#{@job_id} data #{data.inspect}")
      @socket_connection.publish("#{CapistranoSentinel::RequestHooks::SUBSCRIPTION_PREFIX}#{@job_id}", data)
    end

    def on_message(message)
      log_to_file("worker #{@job_id} received:  #{message.inspect}")
      if @socket_connection.succesfull_subscription?(message)
        @successfull_subscription = true
        execute_after_succesfull_subscription
      else
        handle_subscription(message)
      end
    end

    def execute_after_succesfull_subscription
      async.execute_deploy
      @manager.async.wait_task_confirmations_worker(@job)
    end

    def rake_tasks
      @rake_tasks ||= []
    end

    def invocation_chain
      @invocation_chain ||= []
    end

    def execute_deploy
      log_to_file("invocation chain #{@job_id} is : #{@rake_tasks.inspect}")
      check_child_proces
      command = job.fetch_deploy_command
      log_to_file("worker #{@job_id} executes: #{command}")
      @child_process.async.work(@job, command, actor: Actor.current, silent: true, process_sync: :async, runner_status_klass: CapistranoMulticonfigParallel::ChildProcessStatus)
    end

    def check_child_proces
      @child_process = CapistranoMulticonfigParallel::ProcessRunner.new
      Actor.current.link @child_process
      @child_process
    end

    def on_close(code, reason)
      log_to_file("worker #{@job_id} websocket connection closed: #{code.inspect}, #{reason.inspect}")
    end

    def check_gitflow
      return if @job.stage != 'staging' || !@manager.can_tag_staging? || !executed_task?(CapistranoMulticonfigParallel::GITFLOW_TAG_STAGING_TASK)
      mark_for_dispatching_new_job
      @manager.dispatch_new_job(@job, stage: 'production')
    end

    def handle_subscription(message)
      if message_is_about_a_task?(message)
        check_gitflow
        save_tasks_to_be_executed(message)
        async.update_machine_state(message['task']) # if message['action'] == 'invoke'
        log_to_file("worker #{@job_id} state is #{@machine.state}")
        task_approval(message)
      elsif message_is_for_stdout?(message)
        result = Celluloid::Actor[:terminal_server].show_confirmation(message['question'], message['default'])
        publish_rake_event(message.merge('action' => 'stdin', 'result' => result, 'client_action' => 'stdin'))
      elsif message_from_bundler?(message)

        # gem_messsage = job.gem_specs.find{|spec| message['task'].include?(spec.name) }
        # if gem_messsage.present?
        #     async.update_machine_state("insta")
        # else
        async.update_machine_state(message['task'])
        # end
      else
        log_to_file(message, job_id: @job_id)
      end
    end

    def executed_task?(task)
      rake_tasks.present? && rake_tasks.index(task.to_s).present?
    end

    def task_approval(message)
      job_conditions = @manager.job_to_condition[@job_id]
      log_to_file("worker #{@job_id} checks if task : #{message['task'].inspect} is included in #{configuration.task_confirmations.inspect}")
      if job_conditions.present? && configuration.task_confirmations.include?(message['task']) && message['action'] == 'invoke'
        log_to_file("worker #{@job_id} signals approval for task : #{message['task'].inspect}")
        task_confirmation = job_conditions[message['task']]
        task_confirmation[:status] = 'confirmed'
        task_confirmation[:condition].signal(message['task'])
      else
        publish_rake_event(message.merge('approved' => 'yes'))
      end
    end

    def save_tasks_to_be_executed(message)
      log_to_file("worler #{@job_id} current invocation chain : #{rake_tasks.inspect}")
      rake_tasks << message['task'] if rake_tasks.last != message['task']
      invocation_chain << message['task'] if invocation_chain.last != message['task']
    end

    def update_machine_state(name, options = {})
      log_to_file("worker #{@job_id} triest to transition from #{@machine.state} to  #{name}") unless options[:bundler]
      @machine.go_to_transition(name.to_s, options)
      error_message = "worker #{@job_id} task #{name} failed "
      raise(CapistranoMulticonfigParallel::TaskFailed.new(error_message), error_message) if job.failed? # force worker to rollback
    end

    def send_msg(channel, message = nil)
      message = message.present? && message.is_a?(Hash) ? { job_id: @job_id }.merge(message) : { job_id: @job_id, message: message }
      log_to_file("worker #{@job_id} triest to send to #{channel} #{message}")
      publish channel, message
    end

    def finish_worker(exit_status)
      log_to_file("worker #{job_id} tries to terminate with exit_status #{exit_status}")
      @manager.mark_completed_remaining_tasks(@job) if Actor.current.alive?
      update_machine_state('FINISHED') if exit_status.zero?
      @manager.workers_terminated.signal('completed') if !@job.marked_for_dispatching_new_job? && @manager.present? && @manager.alive? && @manager.all_workers_finished?
    end

    def notify_finished(exit_status, _runner_status)
      @job.mark_for_dispatching_new_job if exit_status.nonzero?
      @job.exit_status = exit_status
      finish_worker(exit_status)
      return if exit_status.zero?
      error_message = "worker #{@job_id} task  failed with exit status #{exit_status.inspect}  "
      raise(CapistranoMulticonfigParallel::TaskFailed.new(error_message), error_message)
    end

    # def inspect
    #   to_s
    # end
    #
    # def to_s
    #    "#<#{self.class}(#{Actor.current.mailbox.address.inspect}) alive>"
    # rescue
    #   "#<#{self.class}(#{Actor.current.mailbox.address.inspect}) dead>"
    # end
  end
end
