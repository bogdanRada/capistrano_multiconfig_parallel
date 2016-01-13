require 'fileutils'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class JobCommand
    include FileUtils
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :job
    delegate :app, :stage, :action, :task_arguments, :env_options, :path, to: :job

    def initialize(job)
      @job = job
    end

    def filtered_env_keys
      filtered_env_keys_format(%w(STAGES ACTION))
    end

    def job_stage
      app.present? ? "#{app}:#{stage}" : "#{stage}"
    end

    def capistrano_action
      argv = task_arguments.present? ? "[#{task_arguments}]" : ''
      "#{action}#{argv}"
    end

    def env_option_filtered?(key, filtered_keys_array = [])
      filtered_env_keys.include?(env_key_format(key)) || filtered_keys_array.include?(key.to_s)
    end

    def setup_env_options(options = {})
      array_options = []
      filtered_keys = options.delete(:filtered_keys) || []
      env_options.each do |key, value|
        array_options << "#{env_prefix(key)} #{env_key_format(key)}=#{value}" if value.present? && !env_option_filtered?(key, filtered_keys)
      end
      setup_remaining_flags(array_options, options)
    end

    def setup_remaining_flags(array_options, options)
      array_options << trace_flag if app_debug_enabled?
      array_options.concat(setup_flags_for_job(options))
    end

    def setup_command_line(*args)
      new_arguments, options = setup_command_line_standard(*args)
      setup_env_options(options).concat(new_arguments)
    end

    def job_capistrano_version
      `cd #{job_path} && bundle show capistrano | grep  -Po  'capistrano-([0-9.]+)' | grep  -Po  '([0-9.]+)'`
    end

    def job_path
      path || detect_root
    end

    def gitflow?
      gitflow = `cd #{job_path} && bundle show capistrano-gitflow`
      gitflow.present?
    end

    def to_s
      config_flags = CapistranoMulticonfigParallel.configuration_flags.merge('path' => job_path)
      environment_options = setup_command_line(config_flags).join(' ')
      "RAILS_ENV=#{stage} bundle exec multi_cap #{job_stage} #{capistrano_action}  #{environment_options}"
    end

    def to_json
      { command: to_s }
    end

    def execute_standard_deploy(action = nil)
      run_shell_command(to_s)
    rescue => ex
      rescue_error(ex, 'stderr')
      execute_standard_deploy('deploy:rollback') if action.blank? && @name == 'deploy'
    end

  private

    def run_shell_command(command)
      sh("#{command}")
    end
  end
end
