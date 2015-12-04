require_relative './all'
Gem.find_files('capistrano_multiconfig_parallel/initializers/**/*.rb').each { |path| require path }
module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    class << self
      include CapistranoMulticonfigParallel::ApplicationHelper

      # method used to start
      def start
        execute_with_rescue('stderr') do
          verify_validation
          job_manager = CapistranoMulticonfigParallel::Application.new
          if job_manager.argv[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
            job_manager.start
          else
            Capistrano::Application.new.run
          end
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
