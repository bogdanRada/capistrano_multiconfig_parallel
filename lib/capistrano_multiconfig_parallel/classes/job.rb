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
             :setup_command_line_standard,
             to: :command

    def initialize(options)
      @options = options
    end

    def command
      @command ||= CapistranoMulticonfigParallel::JobCommand.new(self)
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
      failed? || dead? || worker_died? || exit_status.to_i != 0
    end

    def dead?
      status.present? && status.to_s.downcase == 'dead'
    end

    def worker_died?
      status.present? && status.to_s.downcase == 'worker_died'
    end
  end
end
