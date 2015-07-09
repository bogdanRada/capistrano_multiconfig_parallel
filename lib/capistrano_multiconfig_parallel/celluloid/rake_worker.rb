module CapistranoMulticonfigParallel
  # class that handles the rake task and waits for approval from the celluloid worker
  class RakeWorker
    include Celluloid
    include Celluloid::Logger

    attr_accessor :env, :client, :job_id, :action, :task, :task_approved, :successfull_subscription, :subscription_channel, :publisher_channel, :stdin_result

    def work(env, options = {})
      @options = options.stringify_keys
      @env = env
      default_settings
      custom_attributes
      initialize_subscription
    end

    def custom_attributes
      @publisher_channel = "worker_#{@job_id}"
      @action = @options['actor_id'].include?('_count') ? 'count' : 'invoke'
      @task = @options['task']
    end

    def wait_execution(name = task_name, time = 0.1)
      info "Before waiting #{name}"
      Actor.current.wait_for(name, time)
      info "After waiting #{name}"
    end

    def wait_for(name, time)
      info "waiting for #{time} seconds on #{name}"
      sleep time
      info "done waiting on #{name} "
    end

    def default_settings
      @stdin_result = nil
      @job_id = @options['job_id']
      @subscription_channel = @options['actor_id']
      @task_approved = false
      @successfull_subscription = false
    end

    def initialize_subscription
      @client = CelluloidPubsub::Client.connect(actor: Actor.current, enable_debug: debug_enabled?) do |ws|
        ws.subscribe(@subscription_channel)
      end if !defined?(@client) || @client.nil?
    end

    def debug_enabled?
      CapistranoMulticonfigParallel::CelluloidManager.debug_websocket?
    end

    def task_name
      @task.name
    end

    def task_data
      {
        action: @action,
        task: task_name,
        job_id: @job_id
      }
    end

    def publish_new_work(env, new_options = {})
      work(env, @options.merge(new_options))
      after_publishing_new_work
    end

    def after_publishing_new_work
      publish_to_worker(task_data)
    end

    def publish_to_worker(data)
      @client.publish(@publisher_channel, data)
    end

    def on_message(message)
      debug("Rake worker #{@job_id} received after parse #{message}") if debug_enabled?
      if @client.succesfull_subscription?(message)
        publish_subscription_successfull
      elsif message.present? && message['client_action'].blank?
        task_approval(message)
      else
        warn "unknown action: #{message.inspect}" if debug_enabled?
      end
    end

    def msg_for_stdin?(message)
      message['action'] == 'stdin'
    end

    def publish_subscription_successfull
      debug("Rake worker #{@job_id} received  parse #{message}") if debug_enabled?
      publish_to_worker(task_data)
      @successfull_subscription = true
    end

    def stdin_approval(message)
      if @job_id.to_i == message['job_id'].to_i && message['approved'] == 'yes'
        @stdin_result = message
      else
        warn "unknown invocation #{message.inspect}" if debug_enabled?
      end
    end

    def task_approval(message)
      if @job_id.to_i == message['job_id'].to_i && message['task'] == task_name && message['approved'] == 'yes'
        @task_approved = true
      else
        warn "unknown invocation #{message.inspect}" if debug_enabled?
      end
    end

    def on_close(code, reason)
      debug("websocket connection closed: #{code.inspect}, #{reason.inspect}") if debug_enabled?
      terminate
    end
  end
end
