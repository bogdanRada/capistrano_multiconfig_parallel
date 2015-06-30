require_relative './celluloid_worker'
require_relative './terminal_table'
module CapistranoMulticonfigParallel
  # rubocop:disable ClassLength
  class CelluloidManager
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Logger

    cattr_accessor :debug_enabled

    attr_accessor :jobs, :job_to_worker, :worker_to_job, :actor_system, :job_to_condition, :mutex, :registration_complete

    attr_reader :worker_supervisor, :workers
    trap_exit :worker_died

    def initialize(job_manager)
      # start SupervisionGroup
      @worker_supervisor = Celluloid::SupervisionGroup.run!
      @job_manager = job_manager
      @registration_complete = false
      # Get a handle on the SupervisionGroup::Member
      @actor_system = Celluloid.boot
      @mutex = Mutex.new
      # http://rubydoc.info/gems/celluloid/Celluloid/SupervisionGroup/Member
      @workers = @worker_supervisor.pool(CapistranoMulticonfigParallel::CelluloidWorker, as: :workers, size: 10)
      # Get a handle on the PoolManager
      # http://rubydoc.info/gems/celluloid/Celluloid/PoolManager
      # @workers = workers_pool.actor
      @conditions = []
      @jobs = {}
      @job_to_worker = {}
      @worker_to_job = {}
      @job_to_condition = {}

      @worker_supervisor.supervise_as(:terminal_server, CapistranoMulticonfigParallel::TerminalTable, Actor.current)
      @worker_supervisor.supervise_as(:web_server, CelluloidPubsub::WebServer, self.class.websocket_config.merge(enable_debug: self.class.debug_websocket?))
    end

    def self.debug_enabled?
      debug_enabled
    end

    def self.debug_websocket?
      websocket_config['enable_debug'].to_s == 'true'
    end

    def self.websocket_config
      config = CapistranoMulticonfigParallel.configuration[:websocket_server]
      config.present? && config.is_a?(Hash) ? config.stringify_keys : {}
    end

    def generate_job_id(job)
      primary_key = @jobs.size + 1
      job['id'] = primary_key
      @jobs[primary_key] = job
      @jobs[primary_key]
      job['id']
    end

    # call to send an actor
    # a job
    def delegate(job)
      job = job.stringify_keys
      job['id'] = generate_job_id(job) if job['worker_action'] != 'worker_died'
      @jobs[job['id']] = job
      job['env_options'][CapistranoMulticonfigParallel::ENV_KEY_JOB_ID] = job['id']
      # debug(@jobs)
      # start work and send it to the background
      @workers.async.work(job, Actor.current)
    end

    # call back from actor once it has received it's job
    # actor should do this asap
    def register_worker_for_job(job, worker)
      job = job.stringify_keys
      if job['id'].blank?
        debug("job id not found. delegating again the job #{job.inspect}") if self.class.debug_enabled?
        delegate(job)
      else
        worker.job_id = job['id'] if worker.job_id.blank?
        @job_to_worker[job['id']] = worker
        @worker_to_job[worker.mailbox.address] = job
        debug("worker #{worker.job_id} registed into manager") if self.class.debug_enabled?
        Actor.current.link worker
        if @job_manager.jobs.size == @job_to_worker.size
          @registration_complete = true
        end
      end
    end

    def process_jobs(&block)
      @job_to_worker.pmap do |_job_id, worker|
        worker.async.start_task
      end
      if block_given?
        block.call
      else
        wait_task_confirmations
      end
      results2 = []
      @job_to_condition.pmap do |_job_id, hash|
        results2 << hash[:last_condition].wait
      end
      @job_manager.condition.signal(results2) if results2.size == @jobs.size
    end

    def need_confirmations?
      CapistranoMulticonfigParallel.configuration.task_confirmation_active.to_s.downcase == 'true'
    end
    
    def wait_task_confirmations
      return unless need_confirmations?
      CapistranoMulticonfigParallel.configuration.task_confirmations.each_with_index do |task, index|
        results = []
        @jobs.pmap do |job_id, _job|
          current_job = @job_to_condition[job_id][:first_condition][index]
          result = current_job.respond_to?(:wait) ? current_job.wait : current_job
          results << result
        end
        if results.size == @jobs.size
          confirm_task_approval(results, task)
        end
      end
    end

    def confirm_task_approval(results, task)
      return unless results.present?
      if results.detect {|x| !x.is_a?(Proc)}
        set :apps_symlink_confirmation, CapistranoMulticonfigParallel.ask_confirm("Do you want  to continue the deployment and execute #{task}?", 'Y/N')
        until fetch(:apps_symlink_confirmation).present?
          sleep(0.1) # keep current thread alive
        end
      end
      return if fetch(:apps_symlink_confirmation).blank? || fetch(:apps_symlink_confirmation).downcase != 'y'
      @jobs.pmap do |job_id, job|
        worker = get_worker_for_job(job_id)
        worker.publish_rake_event('approved' => 'yes',
          'action' => 'invoke',
          'job_id' => job['id'],
          'task' => task
        )
      end
    end

    def get_worker_for_job(job)
      if job.present?
        if job.is_a?(Hash)
          job = job.stringify_keys
          @job_to_worker[job['id']]
        else
          @job_to_worker[job.to_i]
        end
      else
        return nil
      end
    end

    # lookup status of job by asking actor running it
    def get_job_status(job)
      status = nil
      if job.present?
        if job.is_a?(Hash)
          job = job.stringify_keys
          actor = @registered_jobs[job['id']]
          status = actor.status
        else
          actor = @registered_jobs[job.to_i]
          status = actor.status
        end
      end
      status
    end

    def worker_died(worker, reason)
      debug("worker with mailbox #{worker.mailbox.inspect} died  for reason:  #{reason}") if self.class.debug_enabled?
      job = @worker_to_job[worker.mailbox.address]
      @worker_to_job.delete(worker.mailbox.address)
      debug "restarting #{job} on new worker" if self.class.debug_enabled?
      return if job.blank? || job['worker_action'] == 'worker_died'
      return unless job['worker_action'] == 'deploy'
      job = job.merge(:action => 'deploy:rollback', 'worker_action' => 'worker_died')
      delegate(job)
    end
  end
end
