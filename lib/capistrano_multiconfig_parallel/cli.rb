require_relative './all'
Gem.find_files('capistrano_multiconfig_parallel/extensions/**/*.rb').each { |path| require path }
module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    # method used to start
    def self.start
      CapistranoMulticonfigParallel.check_terminal_tty
      CapistranoMulticonfigParallel.original_args = ARGV.dup
      job_manager = CapistranoMulticonfigParallel::Application.new
      if job_manager.can_start?
        job_manager.start
      else
        Capistrano::Application.new.run
      end
    rescue Interrupt
      `stty icanon echo`
      $stderr.puts 'Command cancelled.'
    rescue => error
      $stderr.puts error
      $stderr.puts error.backtrace if error.respond_to?(:backtrace)
      exit(1)
    end
  end
end
