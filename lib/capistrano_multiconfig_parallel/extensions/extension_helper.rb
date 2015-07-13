require 'celluloid/autostart'
require_relative "../celluloid/rake_worker"
module CapistranoMulticonfigParallel
  class ExtensionHelper
    class << self
      def inside_job?
        job_id.present?
      end

      def job_id
        ENV[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
      end
      

      def rake_actor_id
        ENV['count_rake'].present? ? "rake_worker_#{job_id}_count" : "rake_worker_#{job_id}"
      end

      def actor
        CapistranoMulticonfigParallel::RakeWorker.supervise_as(rake_actor_id,
          actor_id: rake_actor_id,
          job_id: job_id) if Celluloid::Actor[rake_actor_id].blank?
        Celluloid::Actor[rake_actor_id]
      end

      def run_the_actor(task, &block)
        actor.work(ENV, task: task)
        actor.wait_execution until actor.task_approved
        return unless actor.task_approved
        stringio = StringIO.new
        CapistranoMulticonfigParallel::OutputStream.hook(stringio)
        CapistranoMulticonfigParallel::InputStream.hook(actor, stringio)
        block.call
        CapistranoMulticonfigParallel::InputStream.unhook
        CapistranoMulticonfigParallel::OutputStream.unhook
      end

    



    end
  end
end
