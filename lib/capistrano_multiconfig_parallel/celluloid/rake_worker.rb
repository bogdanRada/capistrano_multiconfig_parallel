module CapistranoMulticonfigParallel
  # class that handles the rake task and waits for approval from the celluloid worker
  class RakeWorker
    include Celluloid
    include Celluloid::Logger

    attr_accessor :env, :client, :job_id, :action, :task,
                  :task_approved, :successfull_subscription,
                  :subscription_channel, :publisher_channel, :stdin_result

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

    def publish_new_work(env, new_options = {})
      work(env, @options.merge(new_options))
      publish_to_worker(task_data)
     end

    def wait_execution(name = task_name, time = 0.1)
      #    info "Before waiting #{name}"
      Actor.current.wait_for(name, time)
      #  info "After waiting #{name}"
    end

    def wait_for(_name, time)
      # info "waiting for #{time} seconds on #{name}"
      sleep time
      # info "done waiting on #{name} "
    end

    def default_settings
      @stdin_result = nil
      @job_id = @options['job_id']
      @subscription_channel = @options['actor_id']
      @task_approved = false
      @successfull_subscription = false
    end

    def initialize_subscription
      return if defined?(@client) && @client.present?
      @client = CelluloidPubsub::Client.connect(actor: Actor.current, enable_debug: debug_enabled?, channel: @subscription_channel)
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

    def publish_to_worker(data)
      @client.publish(@publisher_channel, data)
    end

    def on_message(message)
      debug("Rake worker #{@job_id} received after parse #{message}") # if debug_enabled?
      if @client.succesfull_subscription?(message)
        debug("Rake worker #{@job_id} received  parse #{message}") if debug_enabled?
        @successfull_subscription = true
        publish_to_worker(task_data)
      elsif message.present? && message['task'].present?
        task_approval(message)
      elsif message.present? && message['action'].present? && message['action'] == 'stdin'
        stdin_approval(message)
      else
        warn "unknown action: #{message.inspect}" if debug_enabled?
      end
    end

    def msg_for_stdin?(message)
      message['action'] == 'stdin'
    end

    def publish_subscription_successfull
    end

    def wait_for_stdin_input
      wait_execution until @stdin_result.present?
      output = @stdin_result.clone
      Actor.current.stdin_result = nil
      output
    end

    def stdin_approval(message)
      if @job_id.to_i == message['job_id'].to_i && message['result'].present? && message['action'] == 'stdin'
        @stdin_result = message['result']
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

    def get_question_details(data)
      question = ''
      default = nil
      if data =~ /(.*)\?*\s*\:*\s*(\([^)]*\))*/m
        question = Regexp.last_match(1)
        default = Regexp.last_match(2)
      end
      question.present? ? [question, default] : nil
    end

    def printing_question?(data)
      get_question_details(data).present?
    end

    def user_prompt_needed?(data)
      return if !printing_question?(data) || @action != 'invoke'

      details = get_question_details(data)
      default = details.second.present? ? details.second : nil
      publish_to_worker(action: 'stdout',
                        question: details.first,
                        default: default.delete('()'),
                        job_id: @job_id)
      wait_for_stdin_input
    end
  end
end
