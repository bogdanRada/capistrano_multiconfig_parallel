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

    def app
      @options.fetch('app', '')
    end

    def stage
      @options.fetch('stage', '')
    end

    def action
      @options.fetch('action', '')
    end

    def task_arguments
      @options.fetch('task_arguments', [])
    end

    def env_options
      env_options = @options.fetch('env_options', {})
      env_options["#{CapistranoMulticonfigParallel::ENV_KEY_JOB_ID}"] = @id
      env_options.reject { |_key, value| value.blank? }
    end

    def finished?
      @status == 'finished'
    end

    def to_s
      to_json
    end
  end
end
