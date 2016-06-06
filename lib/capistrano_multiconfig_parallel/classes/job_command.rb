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
      env_options = setup_env_options(options).concat(new_arguments)
      env_options.unshift(capistrano_action)
      env_options.unshift(job_stage)
      env_options
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

    def all_prerequisites_file
      File.join(root, get_current_gem_name, 'all')
    end

    def required_capistrano_patch
      file = @legacy_capistrano == true ?  "capistrano2" : "rake"
      File.join(job_monkey_patches_dir, file)
    end

    def cap_require
       @legacy_capistrano ? 'capistrano/cli' : 'capistrano/all'
    end

    def capistrano_start
      if @legacy_capistrano
        <<-CMD
        Capistrano::CLI.execute
        CMD
      else
        <<-CMD
        Capistrano::Application.new.run
        CMD
      end
    end

    def fetch_command
#       FileUtils.touch(job_gemfile_multi)
#       File.open(job_gemfile_multi, 'w') do |f|
#         cmd=<<-CMD
# source "https://rubygems.org"
# gem "#{get_current_gem_name}", "#{CapistranoMulticonfigParallel.gem_version}"
# instance_eval(File.read(File.dirname(__FILE__) + "/Gemfile"))
#         CMD
#         f.write(cmd)
#       end
      environment_options = setup_command_line
      command =<<-CMD
      cd #{job_path} && bundle exec ruby -e "
       require 'rubygems'
       require 'bundler'
       require 'bundler/cli'
       require 'bundler/cli/exec'
       require 'bundler/shared_helpers'
       require '#{all_prerequisites_file}'
       require '#{bundler_monkey_patch}'
        Bundler.with_clean_env {
         ENV['RAILS_ENV']='development'
         ENV['BUNDLE_GEMFILE']='#{job_gemfile}'
         ENV['BUNDLE_IGNORE_CONFIG'] = 'true'
         ENV['#{CapistranoMulticonfigParallel::ENV_KEY_JOB_ID}']='#{job.id}'

         Bundler.send(:configure_gem_home_and_path)
         gemfile = Pathname.new(Bundler.default_gemfile).expand_path
         builder = Bundler::Dsl.new
         builder.eval_gemfile(gemfile)
         Bundler.settings.with = ['development']
         definition = Bundler.definition(true)
         #definition.resolve_remotely!
         #definition.lock('#{job_gemfile_multi}.lock')

         definition = builder.to_definition(Bundler.default_lockfile, {})
         definition.validate_ruby!
         Bundler.ui = Bundler::UI::Shell.new
         Bundler.root = Bundler.default_gemfile.dirname.expand_path
         Bundler::Installer.install(Bundler.root, definition, system: true)

         Bundler.ui.confirm('Bundle complete!' + definition.dependencies.count.to_s + 'Gemfile dependencies,' + definition.specs.count.to_s + 'gems now installed.')


         #runtime = Bundler::Runtime.new(Bundler.root, definition)
         #runtime.setup(:default, 'development')

         #ARGV.replace(#{environment_options.to_s.gsub('"', '\'')})

         #require '#{required_capistrano_patch}'
         #require '#{cap_require}'
         ##{capistrano_start}

         Kernel.system('cd #{job_path} && cap #{environment_options.join(' ')}')
        }
      "
        CMD
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
