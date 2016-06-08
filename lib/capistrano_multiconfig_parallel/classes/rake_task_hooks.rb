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
      attr_accessor  :server, :read_sockets, :write_sockets, :actors

      def actors
        @actors ||= {}
      end

      def job_id
         ENV[CapistranoMulticonfigParallel::RakeTaskHooks::ENV_KEY_JOB_ID]
      end

      def publisher_client
        @publisher_client||= UNIXSocket.new("/tmp/multi_cap_job_#{job_id}.sock")
      end

      def subscription_server
        @subscription_server ||= UNIXServer.new("/tmp/multi_cap_rake_#{job_id}.sock")
      end

      def start_server
        @server         = subscription_server
        @read_sockets   = [@server]
        @write_sockets  = []

        handle_sockets(self)
      end

      def handle_sockets(current_instance)
        Thread.new do
          loop do
            readables, writeables, _ = ::IO.select(current_instance.read_sockets, current_instance.write_sockets)
            handle_readables(readables)
          end
        end
      end

      def decode_job(job)
        Marshal.load(Base64.decode64(job))
      end

      def handle_readables(sockets)
        sockets.each do |socket|
          if socket == subscription_server
            conn = socket.accept
            log_to_file("RakeWorker #{@job_id} tries to accept SOCKET: #{socket.inspect}")
            @read_sockets << conn
            @write_sockets << conn
          else
            log_to_file("RakeWorker #{@job_id} tries to check for message in SOCKET: #{socket.inspect}")
            while message = socket.gets
              log_to_file("RakeWorker #{@job_id} tries to decode SOCKET: #{message.inspect}")
              ary = decode_job(message.chomp)
                log_to_file("RakeWorker #{@job_id} has decoded SOCKET: #{ary.inspect} #{ary.class}")
                ary = ary.with_indifferent_access
                log_to_file("RakeWorker #{@job_id} has decoded SOCKET: #{ary.inspect}")
                actor = CapistranoMulticonfigParallel::RakeTaskHooks.actors[ary['job_id']]
                actor.on_message(ary)
            end
          end
        end
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
        CapistranoMulticonfigParallel::RakeTaskHooks.start_server
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
