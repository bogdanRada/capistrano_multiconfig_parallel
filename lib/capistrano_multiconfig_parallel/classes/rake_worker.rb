module CapistranoMulticonfigParallel
  # class that handles the rake task and waits for approval from the celluloid worker
  class RakeWorker

    attr_reader :client, :job_id, :action, :task,
                :task_approved, :successfull_subscription,
                :subscription_channel, :publisher_channel, :stdin_result

    def work(options = {})
      @options = options.stringify_keys
      default_settings
      custom_attributes
      initialize_subscription
    end

    def custom_attributes
      @publisher_channel = "/tmp/multi_cap_job_#{@job_id}.sock"
      @action = @options['action'].present? ? @options['action'] : 'invoke'
      @task = @options['task']
    end

    def publish_new_work(new_options = {})
      work(@options.merge(new_options))
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
      @subscription_channel ="/tmp/multi_cap_rake_#{@job_id}.sock"
      @task_approved = false
      @successfull_subscription = false
    end

    def initialize_subscription
      return if defined?(@client) && @client.present?
      @client = UNIXSocket.new(@publisher_channel)
      start_server
    end

    def start_server
    FileUtils.rm(@subscription_channel) if File.exists?(@subscription_channel)
    @server         = UNIXServer.new(@subscription_channel)
    @read_sockets   = [@server]
    @write_sockets  = []

    Thread.new do
      loop do
        readables, writeables, _ = IO.select(@read_sockets, @write_sockets)
        handle_readables(readables)
        handle_writeables(writeables)
      end
    end
  end

  def handle_readables(sockets)
    sockets.each do |socket|
      if socket == @server
        conn = socket.accept
        @read_sockets << conn
        @write_sockets << conn
      else
      on_message(socket.gets)
      end
    end
  end

    def task_name
      @task.respond_to?(:name) ? @task.name : @task
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
      return unless message.present?
      log_to_file("Rake worker #{@job_id} received after on message:", message)
      if @client.succesfull_subscription?(message)
        publish_subscription_successfull(message)
      elsif message_is_about_a_task?(message)
        task_approval(message)
      elsif msg_for_stdin?(message)
        stdin_approval(message)
      else
        show_warning "unknown message: #{message.inspect}"
      end
    end

    def publish_subscription_successfull(message)
      return unless @client.succesfull_subscription?(message)
      log_to_file("Rake worker #{@job_id} received after publish_subscription_successfull:", message)
      @successfull_subscription = true
      publish_to_worker(task_data)
    end

    def wait_for_stdin_input
      wait_execution until @stdin_result.present?
      output = @stdin_result.clone
      @stdin_result = nil
      output
    end

    def stdin_approval(message)
      return unless msg_for_stdin?(message)
      if @job_id == message['job_id']
        @stdin_result = message.fetch('result', '')
      else
        show_warning "unknown stdin_approval #{message.inspect}"
      end
    end

    def task_approval(message)
      return unless message_is_about_a_task?(message)
      if @job_id == message['job_id'] && message['task'].to_s == task_name.to_s && message['approved'] == 'yes'
        @task_approved = true
      else
        show_warning "unknown task_approval #{message.inspect} #{task_data}"
      end
    end

    def on_close(code, reason)
      log_to_file("websocket connection closed: #{code.inspect}, #{reason.inspect}")
      terminate
    end

    def user_prompt_needed?(data)
      question, default = get_question_details(data)
      log_to_file("Rake worker #{@job_id} tries to determine question #{data.inspect} #{question.inspect} #{default.inspect}")
      return if question.blank? || @action != 'invoke'
      publish_to_worker(action: 'stdout',
                        question: question,
                        default: default.present? ? default.delete('()') : '',
                        job_id: @job_id)
      wait_for_stdin_input
    end
  end
end
