require 'fileutils'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class Job
    include FileUtils
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_accessor :id, :app, :stage, :action, :task_arguments, :env_options, :status, :exit_status
    def initialize(options)
      @id = SecureRandom.random_number(500)
      @app = options.fetch('app', '')
      @stage = options.fetch('stage', '')
      @action = options.fetch('action', '')
      @task_arguments = options.fetch('task_arguments', [])
      @env_options = {}
      @env_options = options.fetch('env_options', {}).each do |key, value|
        @env_options[key] = value if value.present? && !filtered_env_keys.include?(key)
      end
      @env_options["#{CapistranoMulticonfigParallel::ENV_KEY_JOB_ID}"] = @id
    end

    def filtered_env_keys
      %w(STAGES ACTION)
    end

    def finished?
      status == 'finished'
    end

    def job_stage
      @app.present? ? "#{@app}:#{@stage}" : "#{@stage}"
    end

    def capistrano_action(action = @action)
      argv = @task_arguments.present? ? "[#{@task_arguments}]" : ''
      "#{action}#{argv}"
    end

    def setup_command_line_standard(*args)
      array_options = []
      @env_options.each do |key, value|
        array_options << "#{key}=#{value}" if value.present?
      end
      array_options << '--trace' if app_debug_enabled?
      args.each do |arg|
        array_options << arg if arg.present?
      end
      array_options.join(" ")
    end

    def build_capistrano_task(action = nil, env = [])
      action = action.present? ? action : @action
      environment_options = setup_command_line_standard(env)
      "cd #{detect_root} && RAILS_ENV=#{@stage}  bundle exec cap #{job_stage} #{capistrano_action(action)}  #{environment_options}"
    end


    def execute_standard_deploy(action = nil)
      command = build_capistrano_task(action)
      puts("\n\n\n Executing '#{command}' \n\n\n .")
      sh("#{command}")
    rescue => ex
      log_error(ex)
      execute_standard_deploy('deploy:rollback') if action.blank? && @name == 'deploy'
    end

    def to_s
      self.to_json
    end

  end
end
