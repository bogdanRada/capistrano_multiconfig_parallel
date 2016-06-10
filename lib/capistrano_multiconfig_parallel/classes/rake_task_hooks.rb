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

    class << self
      include CapistranoMulticonfigParallel::ApplicationHelper
      attr_accessor  :socket_connection, :actors, :job_id

      def actors
        @actors ||= {}
      end

      def job_id
         ENV[CapistranoMulticonfigParallel::RakeTaskHooks::ENV_KEY_JOB_ID]
      end

      def socket_connection
        @socket_connection = CapistranoMulticonfigParallel::SocketConnection.new(self,
          {
          tcp_socket_enabled: configuration.enable_tcp_socket,
          debug_websocket: configuration.debug_websocket?,
          log_file_path: websocket_config.fetch('log_file_path', nil),
          subscription_channel: nil
          }
        )
      end

      def on_message(message)
        actor = actors[message['job_id']]
        actor.on_message(message)
      end
    end



    attr_accessor :job_id, :task

    def initialize(task = nil)
      @job_id  = ENV[CapistranoMulticonfigParallel::RakeTaskHooks::ENV_KEY_JOB_ID]
      @task = task.respond_to?(:fully_qualified_name) ? task.fully_qualified_name : task
    end

    def automatic_hooks(&block)
      if ENV['multi_secvential'].to_s.downcase == 'false' && job_id.present? && @task.present?
        actor = get_current_actor
        CapistranoMulticonfigParallel::RakeTaskHooks.socket_connection.subscribe_to_channel("rake_worker_#{@job_id}")
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

    private

    def get_current_actor
      @actor ||= CapistranoMulticonfigParallel::RakeWorker.new
      CapistranoMulticonfigParallel::RakeTaskHooks.actors[@job_id] = @actor
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
      data = {job_id: job_id, task: @task}.merge(additionals)
      actor.work(data)
    end

    alias_method :actor, :get_current_actor

  end
end
