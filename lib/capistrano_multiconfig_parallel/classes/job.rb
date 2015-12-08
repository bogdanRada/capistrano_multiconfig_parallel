require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used for defining the job class
  class Job
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :options, :command

    delegate :build_capistrano_task,
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

    def exit_status
      @exit_status ||= nil
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
        verify_empty_option(value)
      end
    end

    def finished?
      @status == 'finished'
    end

    def to_s
      to_json
    end
  end
end
