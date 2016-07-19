require_relative './celluloid_worker'
require_relative './terminal_table'
require_relative './web_server'
require_relative '../helpers/base_actor_helper'
module CapistranoMulticonfigParallel
  # manager class that handles workers
  class CelluloidManager
    include CapistranoMulticonfigParallel::BaseActorHelper
    attr_accessor :jobs, :job_to_worker, :worker_to_job, :job_to_condition, :mutex, :registration_complete, :workers_terminated, :stderr_buffer

    attr_reader :worker_supervisor, :workers, :bundler_workers
    trap_exit :worker_died

    def initialize(job_manager)
      @job_manager = job_manager
      @registration_complete = false
      return if configuration.multi_secvential.to_s.downcase == 'true'
      # start SupervisionGroup
      @worker_supervisor = setup_supervision_group

      # Get a handle on the SupervisionGroup::Member
      @mutex = Mutex.new
      # http://rubydoc.info/gems/celluloid/Celluloid/SupervisionGroup/Member
      @workers = setup_pool_of_actor(@worker_supervisor, actor_name: :workers, type: CapistranoMulticonfigParallel::CelluloidWorker, size: 10)
      #@workers = Celluloid::Actor[:workers].pool
      Actor.current.link @workers
      setup_actor_supervision(@worker_supervisor, actor_name: :terminal_server, type: CapistranoMulticonfigParallel::TerminalTable, args: [Actor.current, @job_manager, configuration.fetch(:terminal, {})])
      setup_actor_supervision(@worker_supervisor, actor_name: :web_server, type: CapistranoMulticonfigParallel::WebServer, args: websocket_config)
      # Get a handle on the PoolManager
      # http://rubydoc.info/gems/celluloid/Celluloid/PoolManager
      # @workers = workers_pool.actor

      @stderr_buffer = StringIO.new
      @conditions = []
      @jobs = {}
      @job_to_worker = {}
      @worker_to_job = {}
      @job_to_condition = {}
    end

    def start_bundler_supervision_if_needed
      return if configuration.check_app_bundler_dependencies.to_s.downcase != 'true'
      @bundler_workers = setup_pool_of_actor(@worker_supervisor, actor_name: :bundler_workers, type: CapistranoMulticonfigParallel::BundlerWorker, size: 10)
      Actor.current.link @bundler_workers
      setup_actor_supervision(@worker_supervisor, actor_name: :bundler_terminal_server, type: CapistranoMulticonfigParallel::BundlerTerminalTable, args: [Actor.current, @job_manager, configuration.fetch(:terminal, {})])
    end

    # call to send an actor
    # a job
    def delegate_job(job, old_job = "")
      @jobs[job.id] = job
      # debug(@jobs)
      # start work and send it to the background
      @workers.work(job, Actor.current, old_job)
    end

    # call back from actor once it has received it's job
    # actor should do this asap
    def register_worker_for_job(job, worker)
      @job_to_worker[job.id] = worker
      @worker_to_job[worker.mailbox.address] = job
      log_to_file("worker #{worker.job_id} registed into manager")
      Actor.current.link worker
      worker.async.start_task if !syncronized_confirmation? || job.rolling_back?
      return unless syncronized_confirmation?
      @registration_complete = true if @job_manager.jobs.size == @jobs.size
    end

    def all_workers_finished?
      @jobs.all? { |_job_id, job| job.work_done?   }
    end

    def process_jobs
      @workers_terminated = Celluloid::Condition.new
      if syncronized_confirmation?
        @job_to_worker.pmap do |_job_id, worker|
          worker.async.start_task
        end
        wait_task_confirmations
      end
      terminal_show
      async.check_workers_done?
      condition = @workers_terminated.wait
      until condition.present?
        sleep(0.1) # keep current thread alive
      end
      log_to_file("all jobs have completed #{condition}")
      terminal_show
    end

    def check_workers_done?
      Thread.new do
        loop do
          if Actor.current.alive? && all_workers_finished?
            @workers_terminated.signal('completed')
            break
          end
        end
      end
    end

    def terminal_show
      Celluloid::Actor[:terminal_server].async.notify_time_change(CapistranoMulticonfigParallel::TerminalTable.topic, type: 'output') if Celluloid::Actor[:terminal_server].alive?
    end

    def apply_confirmations?
      confirmations = configuration.task_confirmations
      confirmations.is_a?(Array) && confirmations.present?
    end

    def syncronized_confirmation?
      !can_tag_staging?
    end

    def apply_confirmation_for_job(job)
      configuration.apply_stage_confirmation.include?(job.stage) && apply_confirmations?
    end

    def setup_worker_conditions(job)
      return unless apply_confirmation_for_job(job)
      hash_conditions = {}
      configuration.task_confirmations.each do |task|
        hash_conditions[task] = { condition: Celluloid::Condition.new, status: 'unconfirmed' }
      end
      @job_to_condition[job.id] = hash_conditions
    end

    def mark_completed_remaining_tasks(job)
      return unless apply_confirmation_for_job(job)
      configuration.task_confirmations.each_with_index do |task, _index|
        fake_result = proc { |sum| sum }
        task_confirmation = @job_to_condition[job.id][task]
        next unless task_confirmation[:status] != 'confirmed'
        log_to_file("worker #{job.id} with action #{job.action} status #{job.status} and exit status #{job.exit_status} tries to mark fake the task #{task} with status #{task_confirmation[:status]}")
        task_confirmation[:status] = 'confirmed'
        task_confirmation[:condition].signal(fake_result)
      end
    end

    def wait_task_confirmations_worker(job)
      return if !apply_confirmation_for_job(job) || !syncronized_confirmation?
      configuration.task_confirmations.each_with_index do |task, _index|
        result = wait_condition_for_task(job.id, task)
        confirm_task_approval(result, task, job)
      end
    end

    def wait_condition_for_task(job_id, task)
      @job_to_condition[job_id][task][:condition].wait
    end

    def wait_task_confirmations
      stage_apply = configuration.apply_stage_confirmation.include?(@job_manager.stage)
      return if !stage_apply || !syncronized_confirmation?
      configuration.task_confirmations.each_with_index do |task, _index|
        results = []
        @jobs.pmap do |job_id, _job|
          result = wait_condition_for_task(job_id, task)
          results << result
        end
        if results.size == @jobs.size && !all_workers_finished?
          confirm_task_approval(results, task)
        end
      end
    end

    def print_confirm_task_approvall(result, task, job)
      return if result.is_a?(Proc)
      message = "Do you want  to continue the deployment and execute #{task.upcase}"
      message += " for JOB #{job.id}" if job.present?
      message += '?'
      if Celluloid::Actor[:terminal_server].present? && Celluloid::Actor[:terminal_server].alive?
        apps_symlink_confirmation = Celluloid::Actor[:terminal_server].show_confirmation(message, 'Y/N')
        until apps_symlink_confirmation.present?
          sleep(0.1) # keep current thread alive
        end
        apps_symlink_confirmation
      else
        'y'
      end
    end

    def confirm_task_approval(result, task, processed_job = nil)
      return unless result.present?
      result = print_confirm_task_approvall(result, task, processed_job)
      return unless action_confirmed?(result)
      @jobs.pmap do |job_id, job|
        worker = get_worker_for_job(job_id)
        if worker.alive?
          worker.publish_rake_event('approved' => 'yes',
          'action' => 'invoke',
          'job_id' => job.id,
          'task' => task
          )
        end
      end
    end

    def get_worker_for_job(job)
      if job.present?
        if job.is_a?(CapistranoMulticonfigParallel::Job)
          @job_to_worker[job.id]
        else
          @job_to_worker[job]
        end
      else
        return nil
      end
    end

    def can_tag_staging?
      @job_manager.can_tag_staging? && @job_manager.tag_staging_exists? &&
      @jobs.find { |_job_id, job| job.stage == 'production' }.blank?
    end

    def dispatch_new_job(job, options = {})
      return unless job.is_a?(CapistranoMulticonfigParallel::Job)
      options.stringify_keys! if options.present?
      env_opts = options['skip_env_options'].present? ? {} : @job_manager.get_app_additional_env_options(job.app, job.stage)
      new_job_options = job.options.except!('id', 'status', 'exit_status').merge('env_options' => job.env_options.merge(env_opts))
      new_job = CapistranoMulticonfigParallel::Job.new(@job_manager, new_job_options.merge(options))
      log_to_file("Trying to DiSPATCH new JOB #{new_job.inspect}")
      async.delegate_job(new_job, job) unless job.rolling_back?
    end

    # lookup status of job by asking actor running it
    def get_job_status(job)
      status = nil
      if job.present?
        if job.is_a?(CapistranoMulticonfigParallel::Job)
          actor = @job_to_worker[job.id]
          status = actor.job_status
        else
          actor = @job_to_worker[job]
          status = actor.job_status
        end
      end
      status
    end

    def worker_died(worker, reason)
      job = @worker_to_job[worker.mailbox.address]
      mailbox = worker.mailbox
      log_to_file("worker_died: worker job #{job.inspect} with mailbox #{mailbox.inspect} and #{mailbox.address.inspect} died  for reason:  #{reason}")
      return true if job.blank? || job.rolling_back? || job.action != 'deploy'
      #job.rollback_changes_to_application
      @worker_to_job.delete(mailbox.address)
      log_to_file("RESTARTING: worker job #{job.inspect} with mailbox #{mailbox.inspect} and #{mailbox.address.inspect} died  for reason:  #{reason}")

      dispatch_new_job(job, skip_env_options: true, action: 'deploy:rollback')
    end
  end
end
