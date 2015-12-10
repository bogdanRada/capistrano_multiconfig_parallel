require_relative '../helpers/application_helper'
require_relative './job_command'
module CapistranoMulticonfigParallel
  # class used for defining the job class
  class Job
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :options, :command
    attr_writer :status, :exit_status

    delegate :job_stage,
             :capistrano_action,
             :build_capistrano_task,
             :execute_standard_deploy,
             :setup_command_line,
             to: :command

    def initialize(application, options)
      @options = options
      @application = application
      @manager = @application.manager
    end

    def env_variable
      CapistranoMulticonfigParallel::ENV_KEY_JOB_ID
    end

    def command
      @command ||= CapistranoMulticonfigParallel::JobCommand.new(self)
    end

    def terminal_env_variables
      setup_command_line(filtered_keys: [env_variable])
    end

    def terminal_row(index)
      [
        { value: (index + 1).to_s },
        { value: id.to_s },
        { value: wrap_string(job_stage) },
        { value: wrap_string(capistrano_action) },
        { value: terminal_env_variables.map { |str| wrap_string(str) }.join("\n") },
        { value: wrap_string(worker_state) }
      ]
    end

    def worker_state
      default = status.to_s.upcase.red
      return default unless @manager.alive?
      worker = @manager.get_worker_for_job(id)
      worker.alive? ? worker.worker_state : default
    end

    def job_writer_attributes
      %w(status exit_status)
    end

    def setup_writer_attributes(options)
      job_writer_attributes.each do |attribute|
        send("#{attribute}=", options.fetch("#{attribute}", send(attribute)))
      end
    end

    def id
      @id ||= @options.fetch('id', SecureRandom.uuid)
    end

    def status
      @status ||= @options.fetch('status', :unstarted)
    end

    def exit_status
      @exit_status ||= @options.fetch('exit_status', nil)
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
        value["#{env_variable}"] = id if hash[:name] == 'env_options'
        verify_empty_options(value)
      end
      # define_method "#{hash[:name]}=" do |value|
      #   self.send("#{hash[:name]}=", value)
      # end
    end

    def finished?
      status == 'finished'
    end

    def failed?
      ['deploy:failed'].include?(status)
    end

    def rolling_back?
      ['deploy:rollback'].include?(action)
    end

    def crashed?
      failed? || dead? || worker_died? || exit_status.present?
    end

    def dead?
      status.present? && status.to_s.downcase == 'dead'
    end

    def worker_died?
      status.present? && status.to_s.downcase == 'worker_died'
    end
  end
end
