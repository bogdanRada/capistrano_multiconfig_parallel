# base module that has the statis methods that this gem is using
module CapistranoMulticonfigParallel
  ENV_KEY_JOB_ID = 'multi_cap_job_id'
  GITFLOW_TAG_STAGING_TASK = 'gitflow:tag_staging'
  GITFLOW_CALCULATE_TAG_TASK = 'gitflow:calculate_tag'
  GITFLOW_VERIFY_UPTODATE_TASK = 'gitflow:verify_up_to_date'

  class << self
    attr_accessor :logger, :original_args

    include CapistranoMulticonfigParallel::Configuration
    include CapistranoMulticonfigParallel::ApplicationHelper
    include CapistranoMulticonfigParallel::CoreHelper

    def enable_logging
      enable_file_logging
      self.logger ||= ::Logger.new(DevNull.new)
      Celluloid.logger = CapistranoMulticonfigParallel.logger
      Celluloid.task_class = Celluloid::TaskThread
    end

    def enable_file_logging
      return if configuration.multi_debug.to_s.downcase != 'true'
      FileUtils.mkdir_p(log_directory) unless File.directory?(log_directory)
      FileUtils.touch(main_log_file) unless File.file?(main_log_file)
      log_file = File.open(main_log_file, 'w')
      log_file.sync = true
      self.logger = ::Logger.new(main_log_file)
    end

    def custom_commands
      {
        'multi ' => {
          stages: 'deploy_multi_stages'
        },
        'single' => {
          stages: 'deploy_multi_stages'
        }
      }
    end
  end
end
