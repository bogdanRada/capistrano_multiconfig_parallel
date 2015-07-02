Rake::Task.class_eval do
  alias_method :original_execute, :execute

  def execute(args = nil)
    job_id = ENV[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]
    if job_id.present?
      run_the_actor(job_id) do
        original_execute(*args)
      end
    else
      original_execute(*args)
    end
  end

  def run_the_actor(job_id)
    rake_actor_id = ENV['count_rake'].present? ? "rake_worker_#{job_id}_count" : "rake_worker_#{job_id}"
    if Celluloid::Actor[rake_actor_id].blank?
      CapistranoMulticonfigParallel::RakeWorker.supervise_as rake_actor_id
      Celluloid::Actor[rake_actor_id].work(ENV, self, rake_actor_id: rake_actor_id)
    else
      Celluloid::Actor[rake_actor_id].publish_new_work(ENV, self)
    end
    until Celluloid::Actor[rake_actor_id].task_approved
      sleep(0.1) # keep current thread alive
    end
    yield if Celluloid::Actor[rake_actor_id].task_approved
  end
end
