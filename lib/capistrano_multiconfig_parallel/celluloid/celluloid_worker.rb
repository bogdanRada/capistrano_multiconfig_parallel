require_relative './child_process'
require_relative './state_machine'
require_relative '../helpers/base_actor_helper'
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
    class TaskFailed < StandardError; end

    attr_accessor :job, :manager, :job_id, :app_name, :env_name, :action_name, :env_options, :machine, :client, :task_argv,
                  :rake_tasks, :current_task_number, # tracking tasks
                  :successfull_subscription, :subscription_channel, :publisher_channel, # for subscriptions and publishing events
                  :job_termination_condition, :worker_state, :invocation_chain, :filename, :worker_log, :exit_status

    def work(job, manager)
      @job = job
      @job_id = job.id
      @worker_state = job.status
      @manager = manager
      @job_confirmation_conditions = []
      log_to_file("worker #{@job_id} received #{job.inspect}")
      @subscription_channel = "worker_#{@job_id}"
      @machine = CapistranoMulticonfigParallel::StateMachine.new(@job, Actor.current)
      @manager.setup_worker_conditions(@job)
      @unix_socket_file = "/tmp/multi_cap_job_#{@job_id}.sock"
      @rake_socket_file = "/tmp/multi_cap_rake_#{@job_id}.sock"
      manager.register_worker_for_job(job, Actor.current)
    end

    def worker_state
      if Actor.current.alive?
        @machine.state.to_s.green
      else
        job.status = 'dead'
        job.status.upcase.red
      end
    end

    def start_task
      log_to_file("exec worker #{@job_id} starts task")
      start_server
    end


    def start_server
        FileUtils.rm(@unix_socket_file) if File.exists?(@unix_socket_file)
        @server         = ::UNIXServer.new(@unix_socket_file)

        @read_sockets   = [@server]
        @write_sockets  = []
        async.execute_after_succesfull_subscription
        #Thread.new do
          loop do
            readables, writeables, _ = ::IO.select(@read_sockets, @write_sockets)
            handle_readables(readables)
          end
        #end
      end

      def handle_readables(sockets)
        sockets.each do |socket|
        #  if socket == @server
            conn = socket.accept
        #    @read_sockets << conn
        #    @write_sockets << conn
        #  else
        while job = conn.gets
        ary = decode_job(job.chomp)
        on_message(ary)
        end
        #  end
        end
      end

      def encode_job(job)
          # remove silly newlines injected by Ruby's base64 library
          Base64.encode64(Marshal.dump(job)).delete("\n")
        end
      def decode_job(job)
    Marshal.load(Base64.decode64(job))
  end


    def publish_rake_event(data)
      @client.puts(encode_job(data))
    end

    def rake_actor_id(_data)
      "rake_worker_#{@job_id}"
    end

    def on_message(message)
      raise message.inspect
      @client = UNIXSocket.new(@rake_socket_file) if File.exists(@rake_socket_file)
      log_to_file("worker #{@job_id} received:  #{message.inspect}")
      if @client.succesfull_subscription?(message)
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
      command = job.command.to_s
      log_to_file("worker #{@job_id} executes: #{command}")
      @child_process.async.work(@job, command, actor: Actor.current, silent: true)
    end

    def check_child_proces
      @child_process = CapistranoMulticonfigParallel::ChildProcess.new
      Actor.current.link @child_process
      @child_process
    end

    def on_close(code, reason)
      log_to_file("worker #{@job_id} websocket connection closed: #{code.inspect}, #{reason.inspect}")
    end

    def check_gitflow
      return if @job.stage != 'staging' || !@manager.can_tag_staging? || !executed_task?(CapistranoMulticonfigParallel::GITFLOW_TAG_STAGING_TASK)
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
      else
        log_to_file(message, @job_id)
      end
    end

    def executed_task?(task)
      rake_tasks.present? && rake_tasks.index(task.to_s).present?
    end

    def task_approval(message)
      job_conditions = @manager.job_to_condition[@job_id]
      if job_conditions.present? && configuration.task_confirmations.include?(message['task']) && message['action'] == 'invoke'
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

    def update_machine_state(name)
      log_to_file("worker #{@job_id} triest to transition from #{@machine.state} to  #{name}")
      @machine.go_to_transition(name.to_s)
      error_message = "worker #{@job_id} task #{name} failed "
      raise(CapistranoMulticonfigParallel::CelluloidWorker::TaskFailed.new(error_message), error_message) if job.failed? # force worker to rollback
    end

    def send_msg(channel, message = nil)
      publish channel, message.present? && message.is_a?(Hash) ? { job_id: @job_id }.merge(message) : { job_id: @job_id, time: Time.now }
    end

    def finish_worker(exit_status)
      log_to_file("worker #{job_id} tries to terminate with exit_status #{exit_status}")
      @manager.mark_completed_remaining_tasks(@job) if Actor.current.alive?
      update_machine_state('FINISHED') if exit_status == 0
      @manager.workers_terminated.signal('completed') if @manager.present? && @manager.alive? && @manager.all_workers_finished?
    end

    def notify_finished(exit_status)
      finish_worker(exit_status)
      return if exit_status == 0
      error_message = "worker #{@job_id} task  failed with exit status #{exit_status.inspect}  "
      raise(CapistranoMulticonfigParallel::CelluloidWorker::TaskFailed.new(error_message), error_message)
    end
  end
end
