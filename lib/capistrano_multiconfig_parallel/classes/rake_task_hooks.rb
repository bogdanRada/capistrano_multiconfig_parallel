require_relative '../celluloid/rake_worker'
require_relative './input_stream'
require_relative './output_stream'
require_relative './rake_invocation_chain'
module CapistranoMulticonfigParallel
  # class used to handle the rake worker and sets all the hooks before and after running the worker
  class RakeTaskHooks
    attr_accessor :task, :env, :rake_task_list, :invocation_chain
    
    def initialize(env, task)
      @env = env
      @task = task
      @rake_task_list = CapistranoMulticonfigParallel::RakeInvocationChain.new(@env, @task)
      @invocation_chain = @rake_task_list.invocation_chain
    end

    def automatic_hooks(&block)
      if job_id.present?
        actor_start_working
        actor.wait_execution until actor.task_approved
        actor_execute_block(&block)
      else
        block.call
      end
    end

  private

    def output_stream
      CapistranoMulticonfigParallel::OutputStream
    end

    def input_stream
      CapistranoMulticonfigParallel::InputStream
    end

    def before_hooks
      stringio = StringIO.new
      output_stream.hook(stringio)
      input_stream.hook(actor, stringio)
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
        actor.work(@env, actor_id: rake_actor_id, job_id: job_id, task: @task, invocation_chain: @invocation_chain)
      else
        actor.publish_new_work(@env, task: @task,invocation_chain: @invocation_chain)
      end
    end

    def supervise_actor
      return unless actor.blank?
      CapistranoMulticonfigParallel::RakeWorker.supervise_as(rake_actor_id)
    end

    def actor
      Celluloid::Actor[rake_actor_id]
    end

    def job_id
      @env[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
    end

    def rake_actor_id
      "rake_worker_#{job_id}"
    end
  end
end
