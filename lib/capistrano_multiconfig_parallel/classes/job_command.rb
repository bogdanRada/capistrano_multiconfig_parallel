require 'fileutils'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class JobCommand
    include FileUtils
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :job, :job_capistrano_version, :legacy_capistrano, :tempfile
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

    def bundle_gemfile_env(gemfile = job_gemfile)
      "BUNDLE_GEMFILE=#{gemfile}"
    end


    def gitflow_enabled?
      gitflow_version = job_gem_version("capistrano-gitflow")
      gitflow_version.present? ? true : false
    end

    def request_handler_gem_name
      "capistrano_sentinel"
    end

    def request_handler_gem_available?
      gitflow_version = job_gem_version(request_handler_gem_name)
      gitflow_version.present? ? true : false
    end

    def job_stage_for_terminal
      app.present? ? "#{app}:#{stage}" : "#{stage}"
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

    def user_home_directory
      user = Etc.getlogin
      Dir.home(user)
    end

    def rvm_bin_path
      @rvm_path ||= `which rvm`
    end

    def bash_bin_path
      @bash_bin_path ||= `which bash`
    end

    def rvm_installed?
      rvm_bin_path.present?
    end

    def create_job_tempfile_command(output)
      @tempfile ||= Tempfile.new(["multi_cap_#{job.id}_command_", ".rb"], encoding: 'utf-8')
      @tempfile.write(output)
      ObjectSpace.undefine_finalizer(@tempfile) # force garbage collector not to remove automatically the file
      @tempfile.close
    end

    def rvm_scripts_path
      File.join(File.dirname(File.dirname(rvm_bin_path)), 'scripts', 'rvm')
    end

    def job_rvmrc_file
      File.join(job_path, '.rvmrc')
    end

    def job_rvmrc_enabled?
      File.exists?(job_rvmrc_file)
    end

    def rvm_enabled_for_job?
      job_rvmrc_enabled? && rvm_installed? && bash_bin_path.present?
    end

    def check_rvm_loaded
      return  "cd #{job_path}" unless rvm_enabled_for_job?
      "source #{rvm_scripts_path} && rvm rvmrc trust #{job_path} && cd #{job_path} && source #{job_rvmrc_file}"
    end

    def fetch_deploy_command
      #  config_flags = CapistranoMulticonfigParallel.configuration_flags.merge("capistrano_version": job_capistrano_version)
      environment_options = setup_command_line.join(' ')
      command = "#{check_rvm_loaded} && if [ `which bundler |wc -l` = 0 ]; then gem install bundler;fi && (#{bundle_gemfile_env(job_gemfile_multi)} bundle check || #{bundle_gemfile_env(job_gemfile_multi)} bundle install ) && WEBSOCKET_LOGGING=#{debug_websocket?} LOG_FILE=#{websocket_config.fetch('log_file_path', nil)} #{bundle_gemfile_env(job_gemfile_multi)} bundle exec cap #{job_stage} #{capistrano_action} #{environment_options}"

      command = "bash --login -c '#{command}'"  if rvm_enabled_for_job?
      command = command.inspect

      command_text =<<-CMD
      require 'rubygems'
      require 'bundler'
      Bundler.with_clean_env {
        ENV['BUNDLE_GEMFILE'] = '#{job_gemfile_multi}'
        ENV['#{CapistranoSentinel::RequestHooks::ENV_KEY_JOB_ID}']='#{job.id}'
        Kernel.exec(#{command})
      }
      CMD

      if rvm_enabled_for_job?
        create_job_tempfile_command(command_text)
        "ruby #{@tempfile.path}"
      else
        <<-CMD
        cd #{job_path} && bundle exec ruby -e "#{command_text}"
        CMD
      end
    end


    def job_capfile
      File.join(job_path, "Capfile")
    end

    def job_gemfile_multi
      File.join(job_path, "Gemfile.multi_cap")
    end

    def prepare_application_for_deployment
      check_handler_available
      prepare_capfile
    end

    def check_handler_available
      #  '#{find_loaded_gem_property(request_handler_gem_name)}'
      #  path: '/home/raul/workspace/github/capistrano_sentinel'
      FileUtils.rm_rf(job_gemfile_multi) if File.exists?(job_gemfile_multi)
      FileUtils.touch(job_gemfile_multi)
      if request_handler_gem_available?
        FileUtils.copy(File.join(job_path, 'Gemfile'), job_gemfile_multi)
      else
        File.open(job_gemfile_multi, 'w') do |f|
          cmd=<<-CMD
          source "https://rubygems.org" do
            gem "#{request_handler_gem_name}", '#{find_loaded_gem_property(request_handler_gem_name)}'
          end
          instance_eval(File.read(File.dirname(__FILE__) + "/Gemfile"))
          CMD
          f.write(cmd)
        end
      end
      FileUtils.copy(File.join(job_path, 'Gemfile.lock'), "#{job_gemfile_multi}.lock")
    end

    def prepare_capfile
      return if File.foreach(job_capfile).grep(/#{request_handler_gem_name}/).any?
      File.open(job_capfile, 'a+') do |f|
        cmd=<<-CMD
        require "#{request_handler_gem_name}"
        CMD
        f.write(cmd)
      end
    end


    def rollback_changes_to_application
      FileUtils.rm_rf(job_gemfile_multi)
      FileUtils.rm_rf("#{job_gemfile_multi}.lock")
      unless request_handler_gem_available?
        File.open(job_capfile, 'r') do |f|
          File.open("#{job_capfile}.tmp", 'w') do |f2|
            f.each_line do |line|
              f2.write(line) unless line.include?(request_handler_gem_name)
            end
          end
        end
        FileUtils.mv "#{job_capfile}.tmp", job_capfile
        FileUtils.rm_rf("#{job_capfile}.tmp")
      end
      FileUtils.rm_rf(@tempfile.path) if defined?(@tempfile) && @tempfile
    end

    def execute_standard_deploy(action = nil)
      run_shell_command(fetch_deploy_command)
    rescue => ex
      rescue_error(ex, 'stderr')
      execute_standard_deploy('deploy:rollback') if action.blank? && @name == 'deploy'
    end

    private

    def get_bash_command(command)
      Shellwords.escape(command)
    end

    def run_shell_command(command)
      sh("#{command}")
    end
  end
end
