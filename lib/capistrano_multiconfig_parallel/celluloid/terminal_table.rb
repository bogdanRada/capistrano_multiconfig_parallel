require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to display the progress of each worker on terminal screen using a table
  class TerminalTable
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Logger
    include CapistranoMulticonfigParallel::ApplicationHelper
    def self.topic
      'sshkit_terminal'
    end

    def initialize(manager, job_manager)
      @manager = manager
      @job_manager = job_manager
      async.run
    end

    def run
      subscribe(CapistranoMulticonfigParallel::TerminalTable.topic, :notify_time_change)
    end

    def notify_time_change(_topic, _message)
      default_headings = ['Job ID', 'Job UUID', 'App/Stage', 'Action', 'ENV Variables', 'Current Task']
      #   default_headings << 'Total'
      #   default_headings << 'Progress'
      table = Terminal::Table.new(title: 'Deployment Status Table', headings: default_headings)
      jobs = @manager.alive? ? @manager.jobs.dup : []
      if jobs.present?
        jobs.each_with_index do |(job_id, job), count|
          add_job_to_table(table, job_id, job, count)
        end
      end
      show_terminal_screen(table)
    rescue => ex
      log_to_file("Terminal Table  client disconnected due to error #{ex.inspect}")
      log_error(ex, 'stderr')
      terminate
    end

    def show_confirmation(message, default)
      exclusive do
        ask_confirm(message, default)
      end
    end

    def show_terminal_screen(table)
      return unless table.rows.present?
      terminal_clear
      #  table.style = { width: 20 }
      puts "\n#{table}\n"
      sleep(0.1)
      @job_manager.condition.signal('completed') if @manager.all_workers_finished?
    end

    def worker_state(job_id, job)
      return unless @manager.alive?
      worker = @manager.get_worker_for_job(job_id)
      worker.alive? ? worker.worker_state : job.status.upcase.red
    end

    def filtered_env_keys
      %w(STAGES ACTION)
    end

    def add_job_to_table(table, job_id, job, index)
      row = [{ value: (index + 1).to_s },
             { value: job_id.to_s },
             { value: job.job_stage },
             { value: job.capistrano_action },
             { value: job.setup_command_line_standard(filtered_keys: [CapistranoMulticonfigParallel::ENV_KEY_JOB_ID]).join("\n") },
             { value: worker_state(job_id, job) }
            ]

      #   if  worker.alive?
      #     row << { value: job.rake_tasks.size }
      #     row << { value: worker_progress(job_id, job) }
      #   else
      #     row << { value: 0 }
      #     row << { value:  worker_state(job_id) }
      #   end
      table.add_row(row)
      table.add_separator
      table
    end

    def terminal_clear
      system('cls') || system('clear') || puts("\e[H\e[2J")
    end

    # def worker_progress(job)
    #   tasks = job.rake_tasks.size
    #   current_task = job.status
    #   show_worker_percent(tasks, current_task, job)
    # end
    #
    # def show_worker_percent(tasks, current_task, job)
    #   task_index = tasks.index(current_task.to_s).to_i + 1
    #   percent = percent_of(task_index, total_tasks)
    #   result  = "Progress [#{format('%.2f', percent)}%]  (executed #{task_index} of #{total_tasks})"
    #   job.crashed? ? result.red : result.green
    # end
    #
    # def percent_of(index, total)
    #   index.to_f / total.to_f * 100.0
    # end
  end
end
