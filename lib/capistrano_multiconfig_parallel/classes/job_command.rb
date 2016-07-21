require 'fileutils'
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class JobCommand
    extend Forwardable
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :job, :job_capistrano_version, :legacy_capistrano, :tempfile, :job_final_gemfile, :job_final_capfile

    def_delegators :@job, :id, :app, :stage, :action, :task_arguments, :env_options, :path

    def initialize(job)
      @job = job
      @job_final_gemfile = job_gemfile_multi
    end

    def lockfile_parser
      if File.exists?(job_gemfile) && File.exists?(job_gemfile_lock)
        @lockfile_parser ||= Bundler::LockfileParser.new(Bundler.read_file("#{job_gemfile_lock}"))
      else
        raise "please install the gems separately for this application #{job_path} and re-try again!"
      end
    end

    def fetch_bundler_check_command(gemfile = job_gemfile)
      "#{check_rvm_loaded} && if [ `which bundler |wc -l` = 0 ]; then gem install bundler;fi && (#{bundle_gemfile_env(gemfile)} bundle check || #{bundle_gemfile_env(gemfile)} bundle install )"
    end

    def fetch_bundler_worker_command
      get_command_script(fetch_bundler_check_command, "bundler")
    end


    def find_capfile(custom_path = job_path)
      @capfile_path ||= find_file_by_names(custom_path, 'capfile').first
    end

    def capfile_name
      find_capfile.present? ? find_capfile.basename : nil
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

    def capistrano_sentinel_name
      "capistrano_sentinel"
    end

    def capistrano_sentinel_available?
      gitflow_version = job_gem_version(capistrano_sentinel_name)
      gitflow_version.present? ? true : false
    end

    def loaded_capistrano_sentinel_version
      find_loaded_gem_property(capistrano_sentinel_name)
    end

    def job_capistrano_sentinel_version
      job_gem_version(capistrano_sentinel_name)
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
        array_options << "#{env_prefix(key, legacy_capistrano)} #{env_key_format(key, legacy_capistrano)}=#{value}" if value.present? && !env_option_filtered?(key, filtered_keys)
      end
      setup_remaining_flags(array_options, options)
    end

    def setup_remaining_flags(array_options, options)
      array_options << trace_flag(legacy_capistrano) if app_debug_enabled?
      array_options.concat(setup_flags_for_job(options))
    end

    def setup_command_line(*args)
      new_arguments, options = setup_command_line_standard(*args)
      setup_env_options(options).concat(new_arguments)
    end

    def job_capistrano_version
      @job_capistrano_version ||= job_gem_version("capistrano")
    end

    def legacy_capistrano_version?
      verify_gem_version(job_capistrano_version, '3.0', operator: '<')
    end

    def legacy_capistrano
      @legacy_capistrano  ||= legacy_capistrano_version? ? true : false
    end

    def capistrano_sentinel_needs_updating?
      if capistrano_sentinel_available?
        loaded_capistrano_sentinel_version == job_capistrano_sentinel_version
      else
        # the capistrano_sentinel is not part of the Gemfile so no need checking if needs updating
        true
      end
    end

    def job_path
      if path.present? && File.directory?(path) && find_capfile(path).present?
        path
      else
        detect_root
      end
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
      @tempfile = Tempfile.new(["multi_cap_#{job.id}_command_", ".rb"], encoding: 'utf-8')
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

    def rvm_bash_prefix(command)
      rvm_enabled_for_job? ? "bash --login -c '#{command}'" : command
    end

    def log_to_worker(message, action = nil)
      if action.present? || action.to_s == id.to_s
        log_to_file(message, job_id: id, prefix: action)
      else
        log_to_file(message)
      end
    end

    def get_command_script(command, action = nil)
      command = rvm_bash_prefix(command)
      command = command.inspect
      command_text =<<-CMD
      require 'rubygems'
      require 'bundler'
      Bundler.with_clean_env {
        Kernel.exec(#{command})
      }
      CMD

      if rvm_enabled_for_job?
        create_job_tempfile_command(command_text)
        log_to_worker("JOB #{@job_id}  created Tempfile #{@tempfile.path} with contents #{File.read(@tempfile.path)}", action)
        "ruby #{@tempfile.path}"
      else
        final_command=<<-CMD
        cd #{job_path} && bundle exec ruby -e "#{command_text}"
        CMD
        log_to_worker("JOB #{@job_id}  prepared command #{final_command}", action)
        final_command
      end
    end


    def fetch_deploy_command
      prepare_application_for_deployment
      #  config_flags = CapistranoMulticonfigParallel.configuration_flags.merge("capistrano_version": job_capistrano_version)
      environment_options = setup_command_line.join(' ')
      command = "#{fetch_bundler_check_command(@job_final_gemfile)} && WEBSOCKET_LOGGING=#{debug_websocket?} LOG_FILE=#{websocket_config.fetch('log_file_path', nil)} #{bundle_gemfile_env(@job_final_gemfile)} bundle exec cap #{job_stage} #{capistrano_action} #{environment_options}"

      if @job_final_capfile != job_capfile
        command += " -f #{@job_final_capfile}"
      end

      get_command_script(command)
    end


    def job_capfile
      File.join(job_path, capfile_name.to_s)
    end

    def job_capfile_multi
      "#{job_capfile}.multi_cap"
    end

    def job_gemfile_multi
      File.join(job_path, "Gemfile.multi_cap")
    end

    def prepare_application_for_deployment
      unless capistrano_sentinel_needs_updating?
        raise "Please consider upgrading the gem #{capistrano_sentinel_name} to version #{loaded_capistrano_sentinel_version} from #{job_capistrano_sentinel_version} in #{job_path} "
      end
      config = @job.application.patched_job_paths.find{|hash| hash[:path] == job_path}
      if config.present?
        @job_final_gemfile = config[:gemfile]
        @job_final_capfile = config[:capfile]
      else
        check_capistrano_sentinel_availability
        prepare_capfile
        @job.application.patched_job_paths << {path: job_path, gemfile: @job_final_gemfile, capfile: @job_final_capfile}
      end
    end

    def check_capistrano_sentinel_availability
      #  '#{find_loaded_gem_property(capistrano_sentinel_name)}'
      #  path: '/home/raul/workspace/github/capistrano_sentinel'
      if capistrano_sentinel_available?
        @job_final_gemfile = job_gemfile
      else
        FileUtils.rm_rf(job_gemfile_multi) if File.exists?(job_gemfile_multi)
        FileUtils.touch(job_gemfile_multi)
        File.open(job_gemfile_multi, 'w') do |f|
          cmd=<<-CMD
          source "https://rubygems.org" do
            gem "#{capistrano_sentinel_name}", '#{find_loaded_gem_property(capistrano_sentinel_name)}'
          end
          instance_eval(File.read(File.dirname(__FILE__) + "/Gemfile"))
          CMD
          f.write(cmd)
        end
        FileUtils.copy(File.join(job_path, 'Gemfile.lock'), "#{job_gemfile_multi}.lock")
      end
    end

    def prepare_capfile
      capfile_valid = File.foreach(job_capfile).grep(/#{capistrano_sentinel_name}/).any?
      if capistrano_sentinel_available? && capfile_valid.present?
        @job_final_capfile = job_capfile
      elsif capfile_valid.blank? && capistrano_sentinel_available?
        @job_final_capfile = job_capfile
        File.open(job_capfile, 'a+') do |f|
          cmd=<<-CMD
          require "#{capistrano_sentinel_name}"
          CMD
          f.write(cmd)
        end
      elsif capistrano_sentinel_available? == false
        @job_final_capfile = job_capfile_multi
        FileUtils.copy(job_capfile, job_capfile_multi)
        File.open(job_capfile_multi, 'a+') do |f|
          cmd=<<-CMD
          require "#{capistrano_sentinel_name}"
          CMD
          f.write(cmd)
        end
      end
    end


    def rollback_changes_to_application
      FileUtils.rm_rf(job_gemfile_multi) if File.exists?(job_gemfile_multi)
      FileUtils.rm_rf("#{job_gemfile_multi}.lock") if File.exists?("#{job_gemfile_multi}.lock")
      FileUtils.rm_rf(job_capfile_multi) if  File.exists?(job_capfile_multi)
      FileUtils.rm_rf(@tempfile.path) if defined?(@tempfile) && @tempfile
    end

    def execute_standard_deploy(action = nil)
      run_shell_command(fetch_deploy_command)
    rescue => ex
      rescue_error(ex, 'stderr')
      execute_standard_deploy('deploy:rollback') if action.blank? && @name == 'deploy'
    end

    private

    def run_shell_command(command)
      Kernel.system("#{command}")
    end
  end
end
