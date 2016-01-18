# base module that has the statis methods that this gem is using
module CapistranoMulticonfigParallel
  ENV_KEY_JOB_ID = 'multi_cap_job_id'
  GITFLOW_TAG_STAGING_TASK = 'gitflow:tag_staging'
  GITFLOW_CALCULATE_TAG_TASK = 'gitflow:calculate_tag'
  GITFLOW_VERIFY_UPTODATE_TASK = 'gitflow:verify_up_to_date'

  class << self
    attr_accessor :logger, :original_args, :config, :config_keys
    include CapistranoMulticonfigParallel::Configuration
    include CapistranoMulticonfigParallel::GemHelper

    def configuration
      @config ||= fetch_configuration
      @config
    end

    def configuration_flags
      default_internal_config.each_with_object({}) do |array_item, hash|
        key = array_item[0].to_s
        value = get_prop_config(key, configuration)
        hash[key] = value.is_a?(Array) ? value.join(',') : value
        hash
      end.except('application_dependencies')
    end

    def enable_logging
      enable_file_logging
      set_celluloid_exception_handling
    end

    def original_args_hash
      multi_fetch_argv((original_args || ARGV).dup)
    end

    def job_id
      original_args_hash.fetch(CapistranoMulticonfigParallel::ENV_KEY_JOB_ID, nil)
    end

    def capistrano_version
      find_loaded_gem_property
    end

    def capistrano_version_2?
      capistrano_version.blank? ? nil : verify_gem_version(capistrano_version, '3.0', operator: '<')
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
