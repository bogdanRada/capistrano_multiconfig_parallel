require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class that handles the rake task and waits for approval from the celluloid worker
  # rubocop:disable ClassLength
  class RakeWorker
    include Celluloid
    include Celluloid::Logger
    include CapistranoMulticonfigParallel::ApplicationHelper

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
      @action = 'invoke'
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
      @client = CelluloidPubsub::Client.connect(actor: Actor.current, enable_debug: debug_websocket?, channel: @subscription_channel)
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
      return unless message.present?
      log_debug('on_message', message)
      if @client.succesfull_subscription?(message)
        publish_subscription_successfull(message)
      elsif msg_for_task?(message) || msg_for_stdin?(message)
        task_approval(message)
        stdin_approval(message)
      else
        show_warning "unknown action: #{message.inspect}"
      end
    end

    def log_debug(action, message)
      log_to_file("Rake worker #{@job_id} received after #{action}: #{message}")
    end

    def msg_for_stdin?(message)
      message['action'] == 'stdin'
    end

    def msg_for_task?(message)
      message['task'].present?
    end

    def publish_subscription_successfull(message)
      return unless @client.succesfull_subscription?(message)
      log_debug('publish_subscription_successfull', message)
      @successfull_subscription = true
      publish_to_worker(task_data)
    end

    def wait_for_stdin_input
      wait_execution until @stdin_result.present?
      output = @stdin_result.clone
      Actor.current.stdin_result = nil
      output
    end

    def stdin_approval(message)
      return unless msg_for_stdin?(message)
      if @job_id.to_i == message['job_id'].to_i && message['result'].present?
        @stdin_result = message['result']
      else
        show_warning "unknown invocation #{message.inspect}"
      end
    end

    def task_approval(message)
      return unless msg_for_task?(message)
      if @job_id.to_i == message['job_id'].to_i && message['task'] == task_name && message['approved'] == 'yes'
        @task_approved = true
      else
        show_warning "unknown invocation #{message.inspect}"
      end
    end

    def on_close(code, reason)
      log_to_file("websocket connection closed: #{code.inspect}, #{reason.inspect}")
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
