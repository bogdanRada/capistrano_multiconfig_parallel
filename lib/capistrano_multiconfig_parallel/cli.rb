require_relative './all'
Gem.find_files('capistrano_multiconfig_parallel/initializers/**/*.rb').each { |path| require path }
module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    class << self
      include CapistranoMulticonfigParallel::ApplicationHelper

      # method used to start
      def start
        check_terminal_tty
        CapistranoMulticonfigParallel.original_args = ARGV.dup
        arguments = multi_fetch_argv(original_args)
        if arguments[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
          run_the_application
        else
          Capistrano::Application.new.run
        end
      end

      def run_the_application
        execute_with_rescue('stderr') do
          configuration_valid?
          CapistranoMulticonfigParallel::Application.new.start
        end
      end
    end
  end
end
