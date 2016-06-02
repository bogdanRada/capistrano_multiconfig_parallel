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
      check_child_proces
    end

    def filtered_env_keys
      %w(STAGES ACTION)
    end

    def bundle_gemfile_env
      "BUNDLE_GEMFILE=#{job_path}/Gemfile"
    end

    def gitflow
      gitflow_command = "#{command_prefix(true)} && #{bundle_gemfile_env} bundle show capistrano-gitflow  | grep  -Po  'capistrano-gitflow-([a-z0-9.]+)'"
      @gitflow_version ||= `#{gitflow_command}`
      @gitflow_version = @gitflow_version.split("\n").last
      @gitflow_version.include?('Could not find') ? false : true
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
      job_cap_version_command = "#{command_prefix(true)} && #{bundle_gemfile_env} bundle show capistrano | grep  -Po  'capistrano-([0-9.]+)' | grep  -Po  '([0-9.]+)'"
      @job_cap_version ||= `#{job_cap_version_command}`
      @job_cap_version = @job_cap_version.split("\n").last
      strip_characters_from_string(@job_cap_version)
    end

    def legacy_capistrano?
      verify_gem_version(job_capistrano_version, '3.0', operator: '<')
    end

    def job_path
      path || detect_root
    end

    def rvm_check
      bash_available = `ls -la /bin/bash 2>/dev/null | awk '{ print $9}'`
      if bash_available.include?("bash")
        `/bin/bash -c 'export rvm_project_rvmrc=1;'`
      end
    end

    def required_initializer
      dir = "#{root}/#{get_current_gem_name}/initializers/"
      file = @legacy_capistrano == true ?  "capistrano2" : "rake"
      File.join(dir, file)
    end

    def capistrano_start
      if @legacy_capistrano
        <<-CMD
         require 'capistrano/cli'
         Capistrano::CLI.execute
         CMD
       else
         <<-CMD
         require 'capistrano/all'
         Capistrano::Application.new.run
         CMD
       end
     end

    def command_prefix(skip_install = false)
      bundle_install = (skip_install == false && path.present?) ? "&& #{bundle_gemfile_env} bundle install" : ''
      rvm_check
      "cd #{job_path} #{bundle_install}"
    end

    def async_execute
      environment_options = setup_command_line.join(' ')
      command =<<-CMD
      bundle exec ruby -e "require 'bundler'; require 'bundler/cli'; require 'bundler/cli/install'
      Bundler.with_clean_env {
        require '#{root}/#{get_current_gem_name}/all'
        require '#{required_initializer}'
        Dir.chdir('#{job_path}')
        BUNDLE_GEMFILE='#{job_path}/Gemfile'
        RAILS_ENV='#{stage}'
        Bundler::CLI.new.install(:debug => true)
        ARGV.clear
        ARGV << '#{job_stage}'
        ARGV << '#{capistrano_action}'
        ARGV << '#{environment_options}'
        #{capistrano_start}
      }"
      CMD
      # %x[
      # #{command_prefix} && \
      # #{bundle_gemfile_env} RAILS_ENV=#{stage} bundle exec cap #{job_stage} #{capistrano_action} #{environment_options}
      # ]
      #command =   "#{command_prefix}  && #{bundle_gemfile_env} RAILS_ENV=#{stage} bundle exec cap #{job_stage} #{capistrano_action} #{environment_options}"
      run_capistrano(command)
    end

      def run_capistrano(command)
        log_to_file("worker #{job.id} executes: #{command}")
        @child_process.async.work(job, command, actor: job.worker, silent: true)
      end

      def check_child_proces
        @child_process ||= CapistranoMulticonfigParallel::ChildProcess.new
        job.worker.link @child_process
        @child_process
      end

    # def to_json
    #   { command: to_s }
    # end

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
