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
        app_path = ARGV.find { |arg| arg.include?('--path') }
        execute_start(arguments[CapistranoMulticonfigParallel::ENV_KEY_JOB_ID], app_path)
      end

      def execute_start(job_id, app_path)
      #  real_path = fetch_real_path(job_id, app_path)
        configuration_valid?
      #  if job_id.blank?
          run_the_application
        # else
        #   ARGV.reject! { |arg| arg_is_in_default_config?(arg) }
        #   log_to_file("worker #{job_id} runs with ARGV #{ARGV.inspect}", job_id: job_id)
        #   run_capistrano(real_path, job_id)
        # end
      end

      # def run_capistrano(app_path, job_id)
      #   cap = File.join(strip_characters_from_string(`cd #{app_path} && bundle show capistrano`), 'bin', 'cap')
      #   raise cap.inspect
      # end

      def before_start
        check_terminal_tty
        CapistranoMulticonfigParallel.original_args = ARGV.dup
      end

      # def fetch_real_path(job_id, app_path)
      #   return if job_id.blank? || app_path.blank?
      #   ARGV.delete(app_path)
      #   real_path = app_path.split('=')[1]
      #   #Dir.chdir(real_path)
      #   real_path
      # end

      def run_the_application
        execute_with_rescue('stderr') do
          CapistranoMulticonfigParallel::Application.new.start
        end
      end
    end
  end
end
