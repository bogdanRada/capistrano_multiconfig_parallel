# base module that has the statis methods that this gem is using
module CapistranoMulticonfigParallel
  ENV_KEY_JOB_ID = 'multi_cap_job_id'
  GITFLOW_TAG_STAGING_TASK = 'gitflow:tag_staging'
  GITFLOW_CALCULATE_TAG_TASK = 'gitflow:calculate_tag'
  GITFLOW_VERIFY_UPTODATE_TASK = 'gitflow:verify_up_to_date'

  class << self
    attr_accessor :logger, :original_args
    include CapistranoMulticonfigParallel::Configuration

    def enable_logging
      enable_file_logging
      Celluloid.logger = logger
      Celluloid.exception_handler do |ex|
        unless ex.is_a?(Interrupt)
          puts format_error(ex)
          log_error(ex)
        end
      end
      Celluloid.task_class = Celluloid::TaskThread
    end

  private

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
