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
        execute_start(arguments[CapistranoMulticonfigParallel::RakeTaskHooks::ENV_KEY_JOB_ID])
      end

      def execute_start(job_id)
        if job_id.blank?
          run_the_application
        else
          ARGV.reject! { |arg| arg_is_in_default_config?(arg) }
          log_to_file("worker #{job_id} runs with ARGV #{ARGV.inspect}", job_id: job_id)
          run_capistrano
        end
      end

      def run_capistrano
        if capistrano_version_2?
          require 'capistrano/cli'
          Capistrano::CLI.execute
        else
          require 'capistrano/all'
          Capistrano::Application.new.run
        end
      end

      def before_start
        check_terminal_tty
        CapistranoMulticonfigParallel.original_args = ARGV.dup
        CapistranoMulticonfigParallel.original_args.each do |arg|
          if arg_is_in_default_config?(arg)
            args = arg.split('=')
            ENV[args[0].tr('--', '')] = args[1]
          end
        end
      end

      def run_the_application
        execute_with_rescue('stderr') do
          CapistranoMulticonfigParallel::Application.new.start
        end
      end
    end
  end
end
