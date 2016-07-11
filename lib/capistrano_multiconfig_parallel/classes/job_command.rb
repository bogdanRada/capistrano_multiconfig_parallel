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

    def bundle_gemfile_env(gemfile = job_gemfile)
      "BUNDLE_GEMFILE='#{gemfile}'"
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

    def job_monkey_patches_dir
      File.join(root, get_current_gem_name, 'patches')
    end

    def bundler_monkey_patch
      File.join(job_monkey_patches_dir, "bundler")
    end

    def fetch_deploy_command
    #  config_flags = CapistranoMulticonfigParallel.configuration_flags.merge("capistrano_version": job_capistrano_version)
      environment_options = setup_command_line.join(' ')
      #{}"cd #{job_path} && gem install bundler && #{bundle_gemfile_env(job_gemfile_multi)} bundle install && #{bundle_gemfile_env(job_gemfile_multi)} bundle exec cap #{job_stage} #{capistrano_action} #{environment_options}"
        command =<<-CMD
        cd #{job_path} && bundle exec ruby -e "
         require 'rubygems'
         require 'bundler'
         require 'bundler/cli'
         require '#{request_handler_gem_name}'
         require '#{bundler_monkey_patch}'
          Bundler.with_clean_env {
           ENV['RAILS_ENV']='development'
           ENV['BUNDLE_GEMFILE']='#{job_gemfile_multi}'
           ENV['#{CapistranoSentinel::RequestHooks::ENV_KEY_JOB_ID}']='#{job.id}'

           Kernel.exec('cd #{job_path} && (bundle check || bundle install) && bundle exec cap #{job_stage} #{capistrano_action} #{environment_options}')
          }
        "
          CMD
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

      def execute_standard_deploy(action = nil)
        run_shell_command(fetch_deploy_command)
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
