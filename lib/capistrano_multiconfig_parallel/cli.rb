require_relative './all'
Gem.find_files('capistrano_multiconfig_parallel/extensions/**/*.rb').each { |path| require path }
module CapistranoMulticonfigParallel
  # this is the class that will be invoked from terminal , and willl use the invoke task as the primary function.
  class CLI
    def self.start
      CapistranoMulticonfigParallel.check_terminal_tty
      CapistranoMulticonfigParallel.original_args = ARGV.dup
      CapistranoMulticonfigParallel::Application.new.run
    rescue Interrupt
      `stty icanon echo`
      $stderr.puts 'Command cancelled.'
    rescue => error
      $stderr.puts error
      exit(1)
    end
  end
end
