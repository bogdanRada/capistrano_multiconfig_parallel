require_relative '../helpers/application_helper'
require_relative './job_command'
module CapistranoMulticonfigParallel
  # class used for defining the job class
  class Job
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :options
    attr_writer :status, :exit_status

    delegate :job_stage,
             :capistrano_action,
             :build_capistrano_task,
             :execute_standard_deploy,
             :setup_command_line,
             to: :command

    def initialize(application, options)
      @options = options.stringify_keys
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

    def worker
      return unless @manager.alive?
      @manager.get_worker_for_job(id)
    end

    def invocation_chain
      worker.present? && worker.alive? ? worker.invocation_chain : []
    end

    def job_progress(chain)
      task_index = chain.index(status.to_s).to_i + 1
      percent = percent_of(task_index, chain.size)
      result  = "Progress [#{format('%.2f', percent)}%]  (executed #{task_index} of #{chain.size})"
      worker.present? && worker.alive? ? result.green : result.red
    end

    def terminal_row
      chain = invocation_chain.dup
      [
        { value: id.to_s },
        { value: wrap_string(job_stage) },
        { value: wrap_string(capistrano_action) },
        { value: terminal_env_variables.map { |str| wrap_string(str) }.join("\n") },
        { value: wrap_string(worker_state) },
        { value: chain.size },
        { value: job_progress(chain) }
      ]
    end

    def row_size
      longest_hash = terminal_row.max_by do |hash|
        hash[:value].size
      end
      (longest_hash[:value].size.to_f / 80.0).ceil
    end

    def worker_state
      default = status.to_s.upcase.red
      worker.alive? ? worker.worker_state : default
    end

    def id
      @id ||= @options.fetch('id', SecureRandom.uuid)
    end

    [
      { name: 'app', default: '' },
      { name: 'stage', default: '' },
      { name: 'action', default: '' },
      { name: 'task_arguments', default: [] },
      { name: 'env_options', default: {} },
      { name: 'status', default: :unstarted },
      { name: 'exit_status', default: nil }
    ].each do |hash|
      define_method hash[:name] do
        value = @options.fetch(hash[:name], hash[:default])
        value["#{env_variable}"] = id if hash[:name] == 'env_options'
        value = verify_empty_options(value)
        instance_variable_set("@#{hash[:name]}", instance_variable_get("@#{hash[:name]}") || value)
      end
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
      worker_died? || failed? || dead? || exit_status.present?
    end

    def dead?
      status.present? && status.to_s.downcase == 'dead'
    end

    def worker_died?
      !worker.alive?
    end

    def to_json
      hash = {}
      %w(id app stage action task_arguments env_options status exit_status).each do |key|
        hash[key] = send(key)
      end
      hash
    end
  end
end
