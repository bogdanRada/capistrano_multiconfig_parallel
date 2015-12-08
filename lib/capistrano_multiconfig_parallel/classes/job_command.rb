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

    def capistrano_action(rake_action = action)
      argv = task_arguments.present? ? "[#{task_arguments}]" : ''
      "#{rake_action}#{argv}"
    end

    def setup_env_options(options = {})
      options.stringify_keys!
      array_options = []
      env_options.each do |key, value|
        array_options << "#{key}=#{value}" if value.present? && (!filtered_env_keys.include?(key) && !options.fetch('filtered_keys', []).include?(key.to_s))
      end
      array_options << '--trace' if app_debug_enabled?
      array_options
    end

    def setup_command_line_standard(*args)
      options = args.extract_options!
      array_options = setup_env_options(options)
      args.each do |arg|
        array_options << arg if arg.present?
      end
      array_options
    end

    def build_capistrano_task(rake_action = nil, env = [])
      rake_action = rake_action.present? ? rake_action : action
      environment_options = setup_command_line_standard(env).join(' ')
      "cd #{detect_root} && RAILS_ENV=#{@stage}  bundle exec multi_cap #{job_stage} #{capistrano_action(rake_action)}  #{environment_options}"
    end

    def execute_standard_deploy(action = nil)
      command = build_capistrano_task(action)
      run_shell_command(command)
    rescue => ex
      log_error(ex)
      execute_standard_deploy('deploy:rollback') if action.blank? && @name == 'deploy'
    end

  private

    def run_shell_command(command)
      puts("\n\n\n Executing '#{command}' \n\n\n .")
      sh("#{command}")
    end
  end
end
