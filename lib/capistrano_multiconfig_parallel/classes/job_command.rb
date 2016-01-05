require 'fileutils'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class JobCommand
    include FileUtils
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :job
    delegate :app, :stage, :action, :task_arguments, :env_options, to: :job

    def initialize(job)
      @job = job
    end

    def filtered_env_keys
      %w(STAGES ACTION)
    end

    def job_stage
      app.present? ? "#{app}:#{stage}" : "#{stage}"
    end

    def capistrano_action
      argv = task_arguments.present? ? "[#{task_arguments}]" : ''
      "#{action}#{argv}"
    end

    def env_option_filtered?(key, filtered_keys_array = [])
      filtered_env_keys.include?(key) || filtered_keys_array.include?(key.to_s)
    end

    def setup_env_options(options = {})
      array_options = []
      env_options.each do |key, value|
        array_options << "#{key}=#{value}" if value.present? && !env_option_filtered?(key, options.fetch(:filtered_keys, []))
      end
      array_options << '--trace' if app_debug_enabled?
      array_options
    end

    def setup_command_line(*args)
      new_arguments, options = setup_command_line_standard(*args)
      setup_env_options(options).concat(new_arguments)
    end

    def to_s
      environment_options = setup_command_line.join(' ')
      "cd #{detect_root} && RAILS_ENV=#{@stage}  bundle exec multi_cap #{job_stage} #{capistrano_action}  #{environment_options}"
    end

    def to_json
      { command: to_s }
    end

    def execute_standard_deploy(action = nil)
      command = build_capistrano_task(action)
      run_shell_command(command)
    rescue => ex
      log_error(ex, 'stderr')
      execute_standard_deploy('deploy:rollback') if action.blank? && @name == 'deploy'
    end

  private

    def run_shell_command(command)
      puts("\n\n\n Executing '#{command}' \n\n\n .")
      sh("#{command}")
    end
  end
end
