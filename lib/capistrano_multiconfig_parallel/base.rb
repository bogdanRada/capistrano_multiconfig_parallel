# base module that has the statis methods that this gem is using
module CapistranoMulticonfigParallel
  ENV_KEY_JOB_ID = 'multi_cap_job_id'
  MULTI_KEY = 'multi'
  SINGLE_KEY = 'single'
  GITFLOW_TAG_STAGING_TASK = 'gitflow:tag_staging'
  GITFLOW_CALCULATE_TAG_TASK = 'gitflow:calculate_tag'
  GITFLOW_VERIFY_UPTODATE_TASK = 'gitflow:verify_up_to_date'

  CUSTOM_COMMANDS = {
    CapistranoMulticonfigParallel::MULTI_KEY => {
      stages: 'deploy_multi_stages'
    },
    CapistranoMulticonfigParallel::SINGLE_KEY => {
      stages: 'deploy_multi_stages'
    }
  }

  class << self
    include CapistranoMulticonfigParallel::Helper
    include CapistranoMulticonfigParallel::Configuration
  end
end
