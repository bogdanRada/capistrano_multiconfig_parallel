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
        execute_start(arguments)
      end

      def execute_start(arguments)
        if arguments[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
          require_relative './application'
          run_the_application
        else
          Capistrano::Application.new.run
        end
      end

      def before_start
        check_terminal_tty
        CapistranoMulticonfigParallel.original_args = ARGV.dup
      end

      def run_the_application
        execute_with_rescue('stderr') do
          configuration_valid?
          CapistranoMulticonfigParallel::Cursor.move_to_home!
          CapistranoMulticonfigParallel::Application.new.start
        end
      end
    end
  end
end
