require_relative '../helpers/application_helper'
require_relative './job_command'
module CapistranoMulticonfigParallel
  # class used for defining the job class
  class Job
    extend Forwardable
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :options, :application, :manager, :bundler_status, :bundler_check_status
    attr_writer :status, :exit_status,  :bundler_status, :new_jobs_dispatched, :will_dispatch_new_job, :bundler_check_status

    def_delegators :@manager, :stderr_buffer


    def initialize(application, options)
      @options = options.stringify_keys
      @application = application
      @manager = @application.manager
      @gitflow ||= command.gitflow_enabled?
    end

    def save_stderr_error(data)
      return unless development_debug?
      return unless @manager.alive?
      stderr_buffer.rewind
      old_data = stderr_buffer.read.dup
      new_data = old_data.to_s + data
      stderr_buffer.write(new_data) if ['aborted!', 'Terminating', 'Error'].any? { |word| new_data.include?(word) }
    end

    def env_variable
      CapistranoMulticonfigParallel.env_job_key_id
    end

    def command
      @command ||= CapistranoMulticonfigParallel::JobCommand.new(self)
    end

    def terminal_env_variables
      setup_command_line(filtered_keys: [env_variable])
    end

    def terminal_row
      if bundler_check_status
        bundler_check_terminal_row
      elsif bundler_status
        bundler_terminal_row
      else
        [
          { value: wrap_string(id.to_s) },
          { value: wrap_string(job_stage_for_terminal) },
          { value: wrap_string(capistrano_action) },
          { value: terminal_env_variables.map { |str| wrap_string(str) }.join("\n") },
          { value: wrap_string(worker_state) }
        ]
      end
    end

    def bundler_check_terminal_row
      [
        { value: wrap_string(id.to_s) },
        { value: wrap_string(File.basename(job.job_path)) },
        { value: wrap_string("bundle check || bundle install") },
        { value: wrap_string(bundler_check_status.to_s) }
      ]
    end

    def bundler_terminal_row
      [
        { value: wrap_string(id.to_s) },
        { value: wrap_string(job_stage_for_terminal) },
        { value: wrap_string("Setting up gems..") },
        { value: terminal_env_variables.map { |str| wrap_string(str) }.join("\n") },
        { value: wrap_string(status.to_s.green) }
      ]
    end

    def row_size
      longest_hash = terminal_row.max_by do |hash|
        hash[:value].size
      end
      (longest_hash[:value].size.to_f / 80.0).ceil
    end

    def worker
      return unless @manager.alive?
      @manager.get_worker_for_job(id)
    end

    def worker_state
      worker_obj = worker
      default = status.to_s.upcase.red
      worker_died? ? default : worker_obj.worker_state
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
      { name: 'path', default: nil },
      { name: 'status', default: :unstarted },
      { name: 'exit_status', default: nil },
      { name: 'bundler_status', default: nil },
      { name: 'bundler_check_status', default: nil },
      { name: 'new_jobs_dispatched', default: [] },
      { name: 'will_dispatch_new_job', default: nil },
    ].each do |hash|
      define_method hash[:name] do
        value = @options.fetch(hash[:name], hash[:default])
        setup_additional_env_variables(value) if hash[:name] == 'env_options'
        value = verify_empty_options(value)
        instance_variable_set("@#{hash[:name]}", instance_variable_get("@#{hash[:name]}") || value)
      end
    end


    def setup_additional_env_variables(value)
      value["#{env_variable}"] = id
      #value["capistrano_version"] = job_capistrano_version
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

    def mark_for_dispatching_new_job
      return if rolling_back?
      self.will_dispatch_new_job = new_jobs_dispatched.size + 1
    end

    def marked_for_dispatching_new_job?
      will_dispatch_new_job.to_i != new_jobs_dispatched.size
    end

    def new_jobs_dispatched_finished?
      if marked_for_dispatching_new_job?
        sleep(0.1) until will_dispatch_new_job.to_i == new_jobs_dispatched.size
      end
      true
    end

    def crashed?
      worker_died? || failed? || exit_status.present?
    end

    def dead?
      status.present? && status.to_s.downcase == 'dead'
    end

    def worker_died?
      dead? || worker == nil || worker.dead?
    end

    def work_done?
      new_jobs_dispatched_finished? && (finished? || crashed?)
    end

    def inspect
      to_s
    end

    def to_s
      JSON.generate(to_json)
    end

    def to_json
      hash = {}
      %w(id app stage action task_arguments env_options status exit_status bundler_status will_dispatch_new_job new_jobs_dispatched).each do |key|
        hash[key] = send(key).inspect
      end
      hash
    end

    def method_missing(sym, *args, &block)
      command.public_send(sym, *args, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      command.public_methods.include?(method_name) || super
    end

  end
end
