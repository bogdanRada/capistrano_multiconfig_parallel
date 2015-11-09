require 'celluloid/autostart'
require_relative '../celluloid/rake_worker'
require_relative './input_stream'
require_relative './output_stream'
module CapistranoMulticonfigParallel
  class ExtensionHelper
    attr_accessor :task, :env
    def initialize(env, task)
      @env = env
      @task = task
    end

    def work(&block)
      if job_id.present?
        actor_start_working
        actor.wait_execution until actor.task_approved
        return unless actor.task_approved
        actor_execute_block(&block)
      else
        block.call
      end
    end

  private

    def actor_execute_block(&block)
      stringio = StringIO.new
      CapistranoMulticonfigParallel::OutputStream.hook(stringio)
      CapistranoMulticonfigParallel::InputStream.hook(actor, stringio)
      block.call
      CapistranoMulticonfigParallel::InputStream.unhook
      CapistranoMulticonfigParallel::OutputStream.unhook
    end

    def actor_start_working
      if actor.blank?
        CapistranoMulticonfigParallel::RakeWorker.supervise_as rake_actor_id
        actor.work(@env, actor_id: rake_actor_id, job_id: job_id, task: @task)
      else
        actor.publish_new_work(@env, task: @task)
      end
    end

    def supervise_actor
      CapistranoMulticonfigParallel::RakeWorker.supervise_as(rake_actor_id,
                                                             actor_id: rake_actor_id,
                                                             job_id: job_id) if actor.blank?
    end

    def actor
      Celluloid::Actor[rake_actor_id]
    end

    def job_id
      @env[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
    end

    def rake_actor_id
      @env['count_rake'].present? ? "rake_worker_#{job_id}_count" : "rake_worker_#{job_id}"
    end
  end
end
