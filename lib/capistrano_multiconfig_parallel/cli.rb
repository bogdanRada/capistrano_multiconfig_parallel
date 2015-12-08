require_relative './all'
Gem.find_files('capistrano_multiconfig_parallel/initializers/**/*.rb').each { |path| require path }
module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    class << self
      include CapistranoMulticonfigParallel::ApplicationHelper

      # method used to start
      def start
        verify_validation
        arguments = multi_fetch_argv(ARGV.dup)
        if arguments[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
          execute_with_rescue('stderr') do
            CapistranoMulticonfigParallel::Application.new.start
          end
        else
          Capistrano::Application.new.run
        end
      end

      def verify_validation
        check_terminal_tty
        CapistranoMulticonfigParallel.original_args = ARGV.dup
        CapistranoMulticonfigParallel.configuration_valid?
      end
    end
  end
end
