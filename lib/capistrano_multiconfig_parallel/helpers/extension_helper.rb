module CapistranoMulticonfigParallel
  class ExtensionHelper
    class << self
      
      def inside_job?
        job_id.present?
      end
    
      def job_id
        ENV[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
      end
    
  
      def io_actor_id
        "rake_io_#{job_id}"
      end
     
      def rake_actor_id
        ENV['count_rake'].present? ? "rake_worker_#{job_id}_count" : "rake_worker_#{job_id}"
      end
      
     def run_io_actor
          if Celluloid::Actor[io_actor_id].blank?
          CapistranoMulticonfigParallel::IoWorker.supervise_as io_actor_id
          Celluloid::Actor[io_actor_id].async.work(ENV, actor_id:  io_actor_id, job_id: job_id)
        else
          Celluloid::Actor[io_actor_id].async.publish_new_work(ENV)
        end
     end
     
      def run_stdin_actor
        run_io_actor
        until Celluloid::Actor[io_actor_id].task_approved
          sleep(0.1) # keep current thread alive
        end
        return Celluloid::Actor[io_actor_id].stdin_result  if Celluloid::Actor[io_actor_id].task_approved
      end
      
      
      def run_the_actor(task)
        if Celluloid::Actor[rake_actor_id].blank?
          CapistranoMulticonfigParallel::RakeWorker.supervise_as rake_actor_id
          Celluloid::Actor[rake_actor_id].work(ENV, actor_id: rake_actor_id, job_id: job_id, task: task)
        else
          Celluloid::Actor[rake_actor_id].publish_new_work(ENV, task: task)
        end
        until Celluloid::Actor[rake_actor_id].task_approved
          sleep(0.1) # keep current thread alive
        end
        yield if Celluloid::Actor[rake_actor_id].task_approved
      end
    
    end
  end
end
