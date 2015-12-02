require 'fileutils'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class StandardDeploy
    include FileUtils

    attr_accessor :app, :stage, :action, :task_arguments, :env_options
    def initialize(options)
      @app = options.fetch('app', '')
      @stage = options.fetch('env', '')
      @action = options.fetch('action', '')
      @task_arguments = options.fetch('task_arguments:', [])
      @env_options = options.fetch('env_options', {})
      execute_standard_deploy
    end

    def job_stage
      @app.present? ? "#{@app}:#{@stage}" : "#{@stage}"
    end

    def capistrano_action(action)
      argv = task_arguments.present? ? "[#{@task_arguments}]" : ''
      "#{action}#{argv}"
    end

    def setup_command_line_standard(options)
      opts = ''
      options.each do |key, value|
        opts << "#{key}=#{value} " if value.present?
      end
      opts
    end

    def build_capistrano_task(action = @action, env = {})
      environment_options = setup_command_line_standard(@env_options.merge(env))
      "bundle exec cap #{job_stage} #{capistrano_action(action)}  #{environment_options} --trace"
    end

    def execute_standard_deploy(action = @action)
      command = build_capistrano_task(action)
      puts("\n\n\n Executing '#{command}' \n\n\n .")
      sh("#{command}")
      # rescue => ex
      #   CapistranoMulticonfigParallel.log_message(ex)
      #   execute_standard_deploy('deploy:rollback') if action.blank? && @name == 'deploy'
    end
  end
end
