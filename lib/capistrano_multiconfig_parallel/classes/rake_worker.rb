require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class that handles the rake task and waits for approval from the celluloid worker
  class RakeWorker
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :client, :job_id, :action, :task,
    :task_approved, :stdin_result

    def work(options = {})
      @options = options.stringify_keys
      default_settings
      publish_to_worker(task_data)
    end

    def wait_execution(name = task_name, time = 0.1)
      #    info "Before waiting #{name}"
      wait_for(name, time)
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
      @task_approved = false
      @action = @options['action'].present? ? @options['action'] : 'invoke'
      @task = @options['task']
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
      CapistranoMulticonfigParallel::RakeTaskHooks.publisher_client.puts(encode_data(data))
    end

    def encode_data(job)
      # remove silly newlines injected by Ruby's base64 library
      Base64.encode64(Marshal.dump(job)).delete("\n")
    end

    def on_message(message)
      return if message.blank? || !message.is_a?(Hash)
      message = message.with_indifferent_access
      log_to_file("RakeWorker #{@job_id} received after on message: #{message.inspect}")
      if message_is_about_a_task?(message)
        task_approval(message)
      elsif msg_for_stdin?(message)
        stdin_approval(message)
      else
        show_warning "unknown message: #{message.inspect}"
      end
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
      log_to_file("RakeWorker #{@job_id} #{task_name} task_approval : #{message.inspect}")
      if @job_id == message['job_id'] && message['task'].to_s == task_name.to_s && message['approved'] == 'yes'
        @task_approved = true
      else
        show_warning "unknown task_approval #{message.inspect} #{task_data}"
      end
    end

    def on_close(code, reason)
      log_to_file("RakeWorker #{@job_id} websocket connection closed: #{code.inspect}, #{reason.inspect}")
      terminate
    end

    def user_prompt_needed?(data)
      question, default = get_question_details(data)
      log_to_file("RakeWorker #{@job_id} tries to determine question #{data.inspect} #{question.inspect} #{default.inspect}")
      return if question.blank? || @action != 'invoke'
      publish_to_worker(action: 'stdout',
      question: question,
      default: default.present? ? default.delete('()') : '',
      job_id: @job_id)
      wait_for_stdin_input
    end
  end
end
