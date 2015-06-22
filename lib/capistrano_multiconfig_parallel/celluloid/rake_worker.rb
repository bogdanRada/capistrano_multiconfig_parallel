module CapistranoMulticonfigParallel
  # class that handles the rake task and waits for approval from the celluloid worker
  class RakeWorker
    include Celluloid
    include Celluloid::Logger

    attr_accessor :env, :client, :job_id, :action, :task, :task_approved, :successfull_subscription, :subscription_channel, :publisher_channel

    def work(env, task, options = {})
      @options = options.stringify_keys
      @env = env
      @job_id = find_job_id
      @subscription_channel = @options['rake_actor_id']
      @publisher_channel = "worker_#{find_job_id}"
      @action = @options['rake_actor_id'].include?('_count') ? 'count' : 'invoke'
      @task = task
      @task_approved = false
      @successfull_subscription = false
      @client = CelluloidPubsub::Client.connect(actor: Actor.current, enable_debug: CapistranoMulticonfigParallel::CelluloidManager.debug_websocket?) do |ws|
        ws.subscribe(@subscription_channel)
      end if !defined?(@client) || @client.nil?
    end

    def debug_enabled?
      @client.debug_enabled?
    end

    def task_name
      @task.name
    end

    def find_job_id
      @env[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
    end

    def task_data
      {
        action: @action,
        task: task_name,
        job_id: find_job_id
      }
    end

    def publish_new_work(env, task)
      work(env, task, rake_actor_id: @options['rake_actor_id'])
      publish_to_worker(task_data)
    end

    def publish_to_worker(data)
      @client.publish(@publisher_channel, data)
    end

    def on_message(message)
      debug("Rake worker #{find_job_id} received after parse #{message}") if debug_enabled?
      if @client.succesfull_subscription?(message)
        publish_subscription_successfull
      elsif message.present? && message['client_action'].blank?
        task_approval(message)
      else
        warn "unknown action: #{message.inspect}" if debug_enabled?
      end
    end

    def publish_subscription_successfull
      debug("Rake worker #{find_job_id} received  parse #{message}") if debug_enabled?
      publish_to_worker(task_data)
      @successfull_subscription = true
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
