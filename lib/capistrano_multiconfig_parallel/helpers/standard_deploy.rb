require 'fileutils'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class StandardDeploy
    include FileUtils

    attr_accessor :app, :stage, :action, :task_arguments, :env_options
    def initialize(options)
      @app = options.fetch('app', '')
      @stage = options.fetch('env', 'development')
      @action = options.fetch('action', 'deploy')
      @task_arguments = options.fetch('task_arguments:', []).join(',')
      @env_options = options.fetch('env_options', {})
      execute_standard_deploy
    end

    def job_stage
      @app.present? ? "#{@app}:#{@stage}" : "#{@stage}"
    end

    def capistrano_action(_action, arguments = {})
      "action[#{@task_arguments.merge(arguments)}]"
    end

    def setup_command_line_standard(options)
      opts = ''
      options.each do |key, value|
        opts << "#{key}=#{value} " if value.present?
      end
      opts
    end

    def build_capistrano_task(action = @action, arguments = {}, env = {})
      environment_options = setup_command_line_standard(@env_options.merge(env))
      "bundle exec cap #{job_stage} #{capistrano_action(action, arguments)}  #{environment_options}"
    end

    def execute_standard_deploy(action = nil)
      command = build_capistrano_task(action)
      puts("\n\n\n Executing '#{command}' \n\n\n .")
      sh("#{command}")
    rescue => ex
      CapistranoMulticonfigParallel.log_message(ex)
      execute_standard_deploy('deploy:rollback') if action.blank? && @name == 'deploy'
    end
  end
end
