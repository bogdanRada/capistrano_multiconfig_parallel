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
      @lockfile_parser = Bundler::LockfileParser.new(Bundler.read_file("#{job_path}/Gemfile.lock"))
      @legacy_capistrano = legacy_capistrano? ? true : false
      check_child_proces

    end

    def job_gem_version(gem_name)
      gem_spec = @lockfile_parser.specs.find {|spec| spec.name == gem_name}
      gem_spec.version
    end


    def job_rvmrc_enabled?
      rvm = `ls -l #{job_path}/.rvmrc 2>/dev/null | awk '{ print $9}'`
      rvm.include?('.rvmrc')
    end

    def rvm_ruby_version_enabled?
      ruby_versions = `ls -la #{job_path}/.ruby-version #{job_path}/.ruby-gemset 2>/dev/null | awk '{ print $9}'`.split("\n")
      ruby_versions = ruby_versions.map {|a| a.gsub("#{job_path}/", '') } if ruby_versions.present?
      ruby_versions.present? ? [".ruby-version", '.ruby-gemset'].any?{ |file| ruby_versions.include?(file) } : false
    end

    def rvm_versions_conf_enabled?
      versions_conf = `ls -l #{job_path}/.versions.conf 2>/dev/null | awk '{ print $9}'`
      versions_conf.include?('.versions.conf')
    end

    def check_rvm_loaded
      return if !rvm_installed?
      ruby = rvm_load = gemset = nil
      if job_rvmrc_enabled?
        ruby_gemset = strip_characters_from_string(`cat .rvmrc  | tr " " "\n"  |grep -o -P '.*(?<=@).*'`)
        ruby, gemset = ruby_gemset.split('@')
      elsif rvm_ruby_version_enabled?
        ruby =`cat #{job_path}/.ruby-version`
        gemset = `cat #{job_path}/.ruby-gemset`
      elsif rvm_versions_conf_enabled?
        ruby = `cat #{job_path}/.versions.conf | grep -o -P '(?<=ruby=).*'`
        gemset = `cat #{job_path}/.versions.conf | grep -o -P '(?<=ruby-gemset=).*'`
      else
        ruby = `cat #{job_path}/Gemfile | grep -o -P '(?<=ruby=).*'`
        gemset = `cat #{job_path}/Gemfile | grep -o -P '(?<=ruby-gemset=).*'`
        if ruby.blank?
          ruby = `cat #{job_path}/Gemfile  | grep -o -P '(?<=ruby\s).*'`
        end
      end
      rvm_load = "#{ruby.present? ? strip_characters_from_string(ruby) : ''}#{gemset.present? ? "@#{strip_characters_from_string(gemset)}" : ''}"
      "cd #{job_path} && rvm use #{rvm_load}"
    end

    def filtered_env_keys
      %w(STAGES ACTION)
    end

    def bundle_gemfile_env
      "BUNDLE_GEMFILE=#{job_path}/Gemfile"
    end

    def gitflow_enabled?
      gitflow_command = "#{command_prefix(true)} && #{bundle_gemfile_env} bundle show capistrano-gitflow  | grep  -Po  'capistrano-gitflow-([a-z0-9.]+)'"
      gitflow_version = `gitflow_command`
      gitflow_version = gitflow_version.split("\n").last
      gitflow_version.include?('Could not find') ? false : true
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
      job_cap_version_command = "#{command_prefix(true)} && #{bundle_gemfile_env} bundle show capistrano | grep  -Po  'capistrano-([0-9.]+)'"
      @job_cap_version = `#{job_cap_version_command}`
      raise [job_cap_version_command, @job_cap_version].inspect
      @job_cap_version = @job_cap_version.split("\n").last
      strip_characters_from_string(@job_cap_version)
    end

    def legacy_capistrano?
      verify_gem_version(job_capistrano_version, '3.0', operator: '<')
    end

    def job_path
      path || detect_root
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

    def rvm_installed?
      rvm = `rvm help`
      rvm != 'command not found'
    end

    def command_prefix(skip_install = false)
      bundle_install = (skip_install == false && path.present?) ? "&& #{bundle_gemfile_env} bundle install" : ''
      start_command = check_rvm_loaded.present? ? check_rvm_loaded : "cd #{job_path}"
      "#{start_command} #{bundle_install}"
    end

    def async_execute
      environment_options = setup_command_line
      command =<<-CMD
      bundle exec ruby -e "require 'bundler'
      Bundler.with_clean_env {
        require '#{root}/#{get_current_gem_name}/all'
        require '#{required_initializer}'
        Dir.chdir('#{job_path}')
        ENV['RAILS_ENV']='development'
        ENV['BUNDLE_GEMFILE']='#{job_path}/Gemfile'
        ENV['BUNDLE_IGNORE_CONFIG'] = 'true'

        Bundler.configure
        gemfile = Pathname.new(Bundler.default_gemfile).expand_path
        builder = Bundler::Dsl.new
        builder.eval_gemfile(gemfile)
        Bundler.settings.with = ['development', 'test']
        definition = builder.to_definition(Bundler.default_lockfile, {})
        definition.validate_ruby!
        Bundler.ui = Bundler::UI::Shell.new
        Bundler::Installer.install(Bundler.root, definition, system: true)
        Bundler.ui.confirm('Bundle complete!' + definition.dependencies.count.to_s + 'Gemfile dependencies,' + definition.specs.count.to_s + 'gems now installed.')
        Bundler.setup(:default, 'development')

        ARGV.replace(#{environment_options.to_s.gsub('"', '\'')})
        #{capistrano_start}
        }"
        CMD
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
