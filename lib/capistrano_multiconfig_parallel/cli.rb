require_relative './all'
module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    class << self
      include CapistranoMulticonfigParallel::ApplicationHelper

      # method used to start
      def start
        before_start
        arguments = multi_fetch_argv(original_args)
        configuration_valid?
        execute_start(arguments[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID])
      end

      def execute_start(job_id)
        if job_id.blank?
          run_the_application
        else
          ARGV.reject! { |arg| arg_is_in_default_config?(arg) }
          app_path = ARGV.find {|arg| arg.include?('--path')}
          ARGV.delete(app_path)
          log_to_file("worker #{job_id} runs with ARGV #{ARGV.inspect}", job_id: job_id)
          run_capistrano(app_path, job_id)
        end
      end

      def run_capistrano(app_path, job_id)
        real_path = app_path.split('=')[1]
        ARGV << trace_flag if app_debug_enabled?
        arguments = multi_fetch_argv(ARGV.dup)
        array_arguments = arguments.map {|key, value| "#{env_prefix(capistrano_version_2)} #{filtered_env_keys_format(cap_key_format, key)}=#{value}" }
        command = <<-CMD
        bundle exec ruby -e "require 'bundler' ;   Bundler.with_clean_env { %x[cd #{real_path} && bundle install && RAILS_ENV=production bundle exec cap #{array_arguments.join(' ')}] } "
        CMD
        log_to_file("worker #{job_id} tries to run #{command}", job_id: job_id)
        system(command)
      end

      def before_start
        check_terminal_tty
        CapistranoMulticonfigParallel.original_args = ARGV.dup
      end

      def run_the_application
        execute_with_rescue('stderr') do
          CapistranoMulticonfigParallel::Application.new.start
        end
      end
    end
  end
end
