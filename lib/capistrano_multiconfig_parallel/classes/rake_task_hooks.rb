require 'base64'
require 'socket'
require 'fileutils'
require_relative './rake_worker'
require_relative './input_stream'
require_relative './output_stream'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to handle the rake worker and sets all the hooks before and after running the worker
  class RakeTaskHooks
    ENV_KEY_JOB_ID = 'multi_cap_job_id'

    attr_accessor :job_id, :task

    def initialize(task = nil)
      @job_id  = ENV[CapistranoMulticonfigParallel::RakeTaskHooks::ENV_KEY_JOB_ID]
      @task = task.respond_to?(:fully_qualified_name) ? task.fully_qualified_name : task
    end

    def socket_connection
      @socket_connection = CapistranoMulticonfigParallel::SocketConnection.new(actor,
        {
        tcp_socket_enabled:  ENV.fetch('enable_tcp_socket', true) || true,
        debug_websocket: ENV.fetch('debug_websocket', false),
        log_file_path: ENV.fetch('websocket_log_file_path', nil),
        subscription_channel: nil
        }
      )
    end

    def automatic_hooks(&block)
      if ENV['multi_secvential'].to_s.downcase == 'false' && job_id.present? && @task.present?
        socket_connection.subscribe_to_channel("rake_worker_#{@job_id}")
        actor_start_working(action: 'invoke')
        actor.wait_execution until actor.task_approved
        actor_execute_block(&block)
      else
        block.call
      end
    end

    def print_question?(question)
      if job_id.present?
        actor.user_prompt_needed?(question)
      else
        yield if block_given?
      end
    end


    def show_bundler_progress
      actor_start_working({action: "bundle_install"}) if @task.present? && @task.to_s.size > 2
      yield if block_given?
    end

  private

    def actor
      @actor ||= CapistranoMulticonfigParallel::RakeWorker.new
      @actor
    end

    def output_stream
      CapistranoMulticonfigParallel::OutputStream
    end

    def input_stream
      CapistranoMulticonfigParallel::InputStream
    end

    def before_hooks
      stringio = StringIO.new
      output = output_stream.hook(stringio)
      input = input_stream.hook(actor, stringio)
      [input, output]
    end

    def after_hooks
      input_stream.unhook
      output_stream.unhook
    end

    def actor_execute_block(&block)
      before_hooks
      block.call
      after_hooks
    end

    def actor_start_working(additionals = {})
      additionals = additionals.present? ? additionals : {}
      data = {job_id: job_id, task: @task, :socket => socket_connection }.merge(additionals)
      actor.work(data)
    end


  end
end
