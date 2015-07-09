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

      def stdin_result
        Celluloid::Actor[rake_actor_id].stdin_result
      end

      def run_stdin_actor
        Celluloid::Actor[rake_actor_id].wait_execution('stdin') until stdin_result
        output = stdin_result.dup
        Celluloid::Actor[rake_actor_id].stdin_result = nil
        output
      end

      def run_the_actor(task)
        if Celluloid::Actor[rake_actor_id].blank?
          CapistranoMulticonfigParallel::RakeWorker.supervise_as rake_actor_id
          Celluloid::Actor[rake_actor_id].work(ENV, actor_id: rake_actor_id, job_id: job_id, task: task)
        else
          Celluloid::Actor[rake_actor_id].publish_new_work(ENV, task: task)
        end
        until Celluloid::Actor[rake_actor_id].task_approved
          Celluloid::Actor[rake_actor_id].wait_execution
        end
        yield if Celluloid::Actor[rake_actor_id].task_approved
      end
    end
  end
end
