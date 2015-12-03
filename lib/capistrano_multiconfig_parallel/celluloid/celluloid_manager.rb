require_relative './celluloid_worker'
require_relative './terminal_table'
require_relative './web_server'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # rubocop:disable ClassLength
  class CelluloidManager
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Logger
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_accessor :jobs, :job_to_worker, :worker_to_job, :job_to_condition, :mutex, :registration_complete, :workers_terminated

    attr_reader :worker_supervisor, :workers
    trap_exit :worker_died

    def initialize(job_manager)
      # start SupervisionGroup
      @worker_supervisor = Celluloid::SupervisionGroup.run!
      @job_manager = job_manager
      @registration_complete = false
      # Get a handle on the SupervisionGroup::Member
      @mutex = Mutex.new
      # http://rubydoc.info/gems/celluloid/Celluloid/SupervisionGroup/Member
      @workers = @worker_supervisor.pool(CapistranoMulticonfigParallel::CelluloidWorker, as: :workers, size: 10)
      Actor.current.link @workers
      # Get a handle on the PoolManager
      # http://rubydoc.info/gems/celluloid/Celluloid/PoolManager
      # @workers = workers_pool.actor
      @conditions = []
      @jobs = {}
      @job_to_worker = {}
      @worker_to_job = {}
      @job_to_condition = {}
      @worker_supervisor.supervise_as(:terminal_server, CapistranoMulticonfigParallel::TerminalTable, Actor.current, @job_manager)
      @worker_supervisor.supervise_as(:web_server, CapistranoMulticonfigParallel::WebServer, websocket_config)
    end

    def generate_job_id(job)
      @jobs[job['id']] = job
      job['id']
    end

    # call to send an actor
    # a job
    def delegate(job)
      job = job.stringify_keys
      job['id'] = generate_job_id(job) unless job_failed?(job)
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
        log_to_file("job id not found. delegating again the job #{job.inspect}")
        delegate(job)
      else
        start_worker(job, worker)
      end
    end

    def start_worker(job, worker)
      worker.job_id = job['id'] if worker.job_id.blank?
      @job_to_worker[job['id']] = worker
      @worker_to_job[worker.mailbox.address] = job
      log_to_file("worker #{worker.job_id} registed into manager")
      Actor.current.link worker
      worker.async.start_task unless syncronized_confirmation?
      @registration_complete = true if @job_manager.jobs.size == @job_to_worker.size
    end

    def all_workers_finished?
      @job_to_worker.all? { |job_id, _worker| @jobs[job_id]['worker_action'] == 'finished' }
    end

    def process_jobs
      @workers_terminated = Celluloid::Condition.new
      if syncronized_confirmation?
        @job_to_worker.pmap do |_job_id, worker|
          worker.async.start_task
        end
        wait_task_confirmations
      end
      condition = @workers_terminated.wait
      until condition.present?
        sleep(0.1) # keep current thread alive
      end
      log_to_file("all jobs have completed #{condition}")
      Celluloid::Actor[:terminal_server].async.notify_time_change(CapistranoMulticonfigParallel::TerminalTable.topic, type: 'output') if Celluloid::Actor[:terminal_server].alive?
    end

    def apply_confirmations?
      confirmations = app_configuration.task_confirmations
      confirmations.is_a?(Array) && confirmations.present?
    end

    def syncronized_confirmation?
      !@job_manager.can_tag_staging?
    end

    def apply_confirmation_for_worker(worker)
      worker.alive? && app_configuration.apply_stage_confirmation.include?(worker.env_name) && apply_confirmations?
    end

    def setup_worker_conditions(worker)
      return unless apply_confirmation_for_worker(worker)
      hash_conditions = {}
      app_configuration.task_confirmations.each do |task|
        hash_conditions[task] = { condition: Celluloid::Condition.new, status: 'unconfirmed' }
      end
      @job_to_condition[worker.job_id] = hash_conditions
    end

    def mark_completed_remaining_tasks(worker)
      return unless apply_confirmation_for_worker(worker)
      app_configuration.task_confirmations.each_with_index do |task, _index|
        fake_result = proc { |sum| sum }
        task_confirmation = @job_to_condition[worker.job_id][task]
        if task_confirmation[:status] != 'confirmed'
          task_confirmation[:status] = 'confirmed'
          task_confirmation[:condition].signal(fake_result)
        end
      end
    end

    def wait_task_confirmations_worker(worker)
      return if !apply_confirmation_for_worker(worker) || !syncronized_confirmation?
      app_configuration.task_confirmations.each_with_index do |task, _index|
        result = wait_condition_for_task(worker.job_id, task)
        confirm_task_approval(result, task, worker) if result.present?
      end
    end

    def wait_condition_for_task(job_id, task)
      @job_to_condition[job_id][task][:condition].wait
    end

    def wait_task_confirmations
      stage_apply = app_configuration.apply_stage_confirmation.include?(@job_manager.stage)
      return if !stage_apply || !syncronized_confirmation?
      app_configuration.task_confirmations.each_with_index do |task, _index|
        results = []
        @jobs.pmap do |job_id, _job|
          result = wait_condition_for_task(job_id, task)
          results << result
        end
        if results.size == @jobs.size
          confirm_task_approval(results, task)
        end
      end
    end

    def print_confirm_task_approvall(result, task, worker = nil)
      return if result.is_a?(Proc)
      message = "Do you want  to continue the deployment and execute #{task.upcase}"
      message += " for JOB #{worker.job_id}" if worker.present?
      message += '?'
      apps_symlink_confirmation = Celluloid::Actor[:terminal_server].show_confirmation(message, 'Y/N')
      until apps_symlink_confirmation.present?
        sleep(0.1) # keep current thread alive
      end
    end

    def confirm_task_approval(result, task, worker = nil)
      return unless result.present?
      print_confirm_task_approvall(result, task, worker = nil)
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

    def can_tag_staging?
      @job_manager.can_tag_staging? &&
        @jobs.find { |_job_id, job| job['env'] == 'production' }.blank?
    end

    def dispatch_new_job(job)
      original_env = job['env_options']
      env_opts = @job_manager.get_app_additional_env_options(job['app_name'], job['env'])
      job['env_options'] = original_env.merge(env_opts)
      async.delegate(job)
    end

    def filtered_env_keys
      %w(STAGES ACTION)
    end

    def process_job(job)
      if job['processed']
        @jobs[job['job_id']]
      else
        env_options = {}
        job['env_options'].each do |key, value|
          env_options[key] = value if value.present? && !filtered_env_keys.include?(key)
        end
        {
          'job_id' => job['id'],
          'app_name' => job['app'],
          'env_name' => job['env'],
          'action_name' => job['action'],
          'env_options' => env_options,
          'task_arguments' => job['task_arguments'],
          'job_argv' => job.fetch('job_argv', []),
          'processed' => true
        }
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

    def job_failed?(job)
      job['worker_action'].present? && job['worker_action'] == 'worker_died'
    end

    def worker_died(worker, reason)
      job = @worker_to_job[worker.mailbox.address]
      log_to_file("worker job #{job} with mailbox #{worker.mailbox.inspect} died  for reason:  #{reason}")
      @worker_to_job.delete(worker.mailbox.address)
      return if job.blank? || job_failed?(job)
      return unless job['action_name'] == 'deploy'
      log_to_file "restarting #{job} on new worker"
      job = job.merge(:action => 'deploy:rollback', 'worker_action' => 'worker_died')
      delegate(job)
    end
  end
end
