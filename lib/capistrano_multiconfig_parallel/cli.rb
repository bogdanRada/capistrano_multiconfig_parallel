require_relative './all'
module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    class << self
      include CapistranoMulticonfigParallel::ApplicationHelper

      # method used to start
      def start
        before_start
        configuration_valid?
        run_the_application
      end

      def before_start(argv = ARGV)
        check_terminal_tty
        CapistranoMulticonfigParallel.original_args = argv.dup
      end

      def run_the_application
        begin
          application = CapistranoMulticonfigParallel::Application.new
          execute_with_rescue('stderr') do
            application.start
          end
        ensure
          application.jobs_restore_application_state if application.present?
        end
      end
    end
  end
end
