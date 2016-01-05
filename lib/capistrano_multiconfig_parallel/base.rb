# base module that has the statis methods that this gem is using
module CapistranoMulticonfigParallel
  ENV_KEY_JOB_ID = 'multi_cap_job_id'
  GITFLOW_TAG_STAGING_TASK = 'gitflow:tag_staging'
  GITFLOW_CALCULATE_TAG_TASK = 'gitflow:calculate_tag'
  GITFLOW_VERIFY_UPTODATE_TASK = 'gitflow:verify_up_to_date'

  class << self
    attr_accessor :logger, :original_args, :invocation_chains
    include CapistranoMulticonfigParallel::Configuration
    include CapistranoMulticonfigParallel::CoreHelper

    def enable_logging
      enable_file_logging
      set_celluloid_exception_handling
    end

    def fetch_invocation_chains(job_id = nil)
      self.invocation_chains ||=  {}
      self.invocation_chains[job_id] = [] if job_id.present?
      job_id.present?  ? invocation_chains[job_id] : invocation_chains
    end

    def get_job_invocation_chain(job_id, task = nil, position = nil)
      tasks = fetch_invocation_chains(job_id)
      return tasks if task.blank?
      position = position.present? ? position : tasks.size
      fetch_invocation_chains(job_id).insert(position, task) if job_chain_task_index(job_id, task).blank?
    end

     def job_chain_task_index(job_id, task_name)
      return if job_id.blank? || task_name.blank?
      fetch_invocation_chains(job_id).index(task_name)
    end

    private

   

    def set_celluloid_exception_handling
      Celluloid.logger = logger
      Celluloid.task_class = Celluloid::TaskThread
      Celluloid.exception_handler do |ex|
        unless ex.is_a?(Interrupt)
        rescue_error(ex, 'stderr')
        end
      end
    end

    def enable_file_logging
      if configuration.multi_debug.to_s.downcase == 'true'
        enable_main_log_file
        self.logger = ::Logger.new(main_log_file)
      else
        self.logger ||= ::Logger.new(DevNull.new)
      end
    end
  end
end
