require_relative './all'
Gem.find_files('capistrano_multiconfig_parallel/initializers/**/*.rb').each { |path| require path }
module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    class << self
      # method used to start
      def start
        verify_validation
        start_work
      rescue Interrupt
        rescue_interrupt
      rescue => error
        rescue_error(error)
      end

      def rescue_interrupt
        `stty icanon echo`
        $stderr.puts 'Command cancelled.'
      end

      def rescue_error(error)
        $stderr.puts error
        $stderr.puts error.backtrace if error.respond_to?(:backtrace)
        exit(1)
      end

      def verify_validation
        CapistranoMulticonfigParallel.check_terminal_tty
        CapistranoMulticonfigParallel.original_args = ARGV.dup
        CapistranoMulticonfigParallel.configuration_valid?
      end

      def start_work
        job_manager = CapistranoMulticonfigParallel::Application.new
        if job_manager.argv[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID].blank?
          job_manager.start
        else
          Capistrano::Application.new.run
        end
      end
    end
  end
end
