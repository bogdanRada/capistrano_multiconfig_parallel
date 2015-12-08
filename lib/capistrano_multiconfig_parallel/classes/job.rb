require_relative '../helpers/application_helper'
require_relative './job_command'
module CapistranoMulticonfigParallel
  # class used for defining the job class
  class Job
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :options, :command

    delegate :job_stage,
    :capistrano_action,
    :build_capistrano_task,
    :execute_standard_deploy,
    :setup_command_line_standard,
    to: :command

    def initialize(options)
      @options = options
      @command = CapistranoMulticonfigParallel::JobCommand.new(self)
    end

    def id
      @id ||= SecureRandom.uuid
    end

    def status
      @status ||= :unstarted
    end

    def status=(value)
      @status = value
    end

    def exit_status
      @exit_status ||= nil
    end

    def exit_status=(value)
      @exit_status = value
    end

    [
      { name: 'app', default: '' },
      { name: 'stage', default: '' },
      { name: 'action', default: '' },
      { name: 'task_arguments', default: [] },
      { name: 'env_options', default: {} }
    ].each do |hash|
      define_method hash[:name] do
        value = @options.fetch(hash[:name], hash[:default])
        value["#{CapistranoMulticonfigParallel::ENV_KEY_JOB_ID}"] = id if hash[:name] == 'env_options'
        verify_empty_options(value)
      end
    end

    def finished?
      @status == 'finished'
    end

    def crashed?
      crashing_actions = ['deploy:rollback', 'deploy:failed']
      crashing_actions.include?(action) || crashing_actions.include?(status) || failed?
    end

    def failed?
      status.present? && status == 'worker_died'
    end


  end
end
