require 'fileutils'
module CapistranoMulticonfigParallel
  # class used to find application dependencies
  class StandardDeploy
    extend FileUtils

    def self.setup_command_line_standard(options)
      opts = ''
      options.each do |key, value|
        opts << "#{key}=#{value} " if value.present?
      end
      opts
    end

    def self.execute_standard_deploy(options)
      app = options.fetch('app', '')
      stage = options.fetch('env', 'development')
      action_name = options.fetch('action', 'deploy')
      action = "#{action_name}[#{options.fetch('task_arguments:', []).join(',')}]"
      arguments = setup_command_line_standard(options.fetch('env_options', {}))
      job_stage = app.present? ? "#{app}:#{stage}" : "#{stage}"

      command = "bundle exec cap #{job_stage} #{action}  #{arguments}"
      puts("\n\n\n Executing '#{command}' \n\n\n .")
      sh("#{command}")
    rescue => ex
      CapistranoMulticonfigParallel.log_message(ex)
      if @name == 'deploy'
        begin
          action = "deploy:rollback[#{options.fetch(:task_arguments, []).join(',')}]"
          command = "bundle exec cap #{app}:#{stage} #{action} #{arguments}"
          puts("\n\n\n Executing #{command} \n\n\n .")
          sh("#{command}")
        rescue => exception
          CapistranoMulticonfigParallel.log_message(exception)
          # nothing to do if rollback fails
        end
      end
    end
  end
end
