require_relative '../celluloid/rake_worker'
require_relative './input_stream'
require_relative './output_stream'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to handle the rake worker and sets all the hooks before and after running the worker
  class RakeTaskHooks
    include CapistranoMulticonfigParallel::ApplicationHelper
    attr_accessor :job_id, :task
    def initialize(task = nil)
      @job_id = ENV[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
      @task = task.respond_to?(:fully_qualified_name) ? task.fully_qualified_name : task
    end

    def automatic_hooks(&block)
      if configuration.multi_secvential.to_s.downcase == 'false' && job_id.present? && @task.present?
        actor_start_working
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
        yield if block.given?
      end
    end

  private

    def actor
      Celluloid::Actor[rake_actor_id]
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

    def actor_start_working
      if actor.blank?
        supervise_actor
        actor.work(actor_id: rake_actor_id, job_id: job_id, task: @task)
      else
        actor.publish_new_work(task: @task)
      end
    end

    def supervise_actor
      return unless actor.blank?
      CapistranoMulticonfigParallel::RakeWorker.supervise_as(rake_actor_id)
    end

    def rake_actor_id
      "rake_worker_#{job_id}"
    end
  end
end
