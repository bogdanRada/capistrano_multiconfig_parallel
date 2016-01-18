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
        execute_start(arguments[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID])
      end

      def execute_start(job_id)
        if job_id.blank?
          run_the_application
        else
          ARGV.reject! { |arg| arg_is_in_default_config?(arg) }
          log_to_file("worker #{job_id} runs with ARGV #{ARGV.inspect}", job_id: job_id)
          require_capistrano
          run_capistrano
        end
      end

      def require_capistrano
        job_path = CapistranoMulticonfigParallel.configuration[:job_path] || detect_root
        capistrano_path = gem_path('capistrano', job_path)
        $LOAD_PATH.unshift(File.join(capistrano_path, 'lib'))
        cap_file = capistrano_version_2? ? 'capistrano/cli' : 'capistrano/all'
        raise job_path.inspect
        raise Gem.find_files("lib/#{cap_file}.rb").inspect#.each{|file| require file}
        Gem.find_files('capistrano_multiconfig_parallel/initializers/**/*.rb').each { |path| require path }
      end

      def run_capistrano
        if capistrano_version_2?
          Capistrano::CLI.execute
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
          CapistranoMulticonfigParallel::Application.new.start
        end
      end
    end
  end
end
