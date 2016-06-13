require 'fileutils'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class JobCommand
    include FileUtils
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :job, :job_capistrano_version, :legacy_capistrano
    delegate :id, :app, :stage, :action, :task_arguments, :env_options, :path, to: :job

    def initialize(job)
      @job = job
      @legacy_capistrano = legacy_capistrano? ? true : false
    end

    def lockfile_parser
      if File.exists?(job_gemfile_lock)
        @lockfile_parser ||= Bundler::LockfileParser.new(Bundler.read_file("#{job_gemfile_lock}"))
      else
        raise RuntimeError, "please install the gems separately for this application #{job_path} and re-try again!"
      end
    end

    def gem_specs
      @specs = lockfile_parser.specs
    end

    def job_gemfile
      File.join(job_path, 'Gemfile')
    end

    def job_gemfile_lock
      File.join(job_path, 'Gemfile.lock')
    end

    def job_gem_version(gem_name)
      gem_spec = gem_specs.find {|spec| spec.name == gem_name}
      gem_spec.present? ? gem_spec.version.to_s : nil
    end

    def filtered_env_keys
      %w(STAGES ACTION)
    end

    def bundle_gemfile_env
      "BUNDLE_GEMFILE=#{job_gemfile}"
    end

    def gitflow_enabled?
     gitflow_version = job_gem_version("capistrano-gitflow")
      gitflow_version.present? ? true : false
    end

    def job_stage
      multi_apps?(job_path) && app.present? ? "#{app}:#{stage}" : "#{stage}"
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
        array_options << "#{env_prefix(key, @legacy_capistrano)} #{env_key_format(key, @legacy_capistrano)}=#{value}" if value.present? && !env_option_filtered?(key, filtered_keys)
      end
      setup_remaining_flags(array_options, options)
    end

    def setup_remaining_flags(array_options, options)
      array_options << trace_flag(@legacy_capistrano) if app_debug_enabled?
      array_options.concat(setup_flags_for_job(options))
    end

    def setup_command_line(*args)
      new_arguments, options = setup_command_line_standard(*args)
      setup_env_options(options).concat(new_arguments)
    end

    def job_capistrano_version
      @job_capistrano_version ||= job_gem_version("capistrano")
    end

    def legacy_capistrano?
      verify_gem_version(job_capistrano_version, '3.0', operator: '<')
    end

    def job_path
      path || detect_root
    end

    def command_prefix
      bundle_install = path.present? ? "&& #{bundle_gemfile_env} bundle install" : ''
      "cd #{job_path} #{bundle_install}"
    end

    def to_s
      config_flags = CapistranoMulticonfigParallel.configuration_flags
      environment_options = setup_command_line(config_flags).join(' ')
      "#{command_prefix} && #{bundle_gemfile_env} bundle exec multi_cap #{job_stage} #{capistrano_action} #{environment_options}"
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
