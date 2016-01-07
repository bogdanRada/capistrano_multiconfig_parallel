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
        execute_start(arguments)
      end

      def execute_start(arguments)
        if arguments[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
          run_the_application
        else
          ARGV.reject!{ |arg| configuration.keys.map(&:to_s).include?(arg.split('=')[0].tr('--','')) }
          if CapistranoMulticonfigParallel.capistrano_version_2?
            require 'capistrano/cli'
            Capistrano::CLI.execute
          else
            require 'capistrano/all'
            Capistrano::Application.new.run
          end
        end
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
