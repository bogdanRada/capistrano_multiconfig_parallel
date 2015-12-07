require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to display the progress of each worker on terminal screen using a table
  # rubocop:disable ClassLength
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

    def notify_time_change(topic, message)
      return unless topic == CapistranoMulticonfigParallel::TerminalTable.topic
      default_headings = ['Job ID', 'Job UUID', 'App/Stage', 'Action', 'ENV Variables', 'Current Task']
      #   default_headings << 'Total'
      #   default_headings << 'Progress'
      table = Terminal::Table.new(title: 'Deployment Status Table', headings: default_headings)

      if @manager.alive? && @manager.jobs.present? && message_valid?(message)
        count = 0
        last_job_id = @manager.jobs.keys.last.to_i
        @manager.jobs.each do |job_id, job|
          count += 1
          add_job_to_table(table, job_id, job,  count, last_job_id)
        end
      end
      show_terminal_screen(table)
    rescue => ex
      log_to_file("Terminal Table  client disconnected due to error #{ex.inspect}")
      log_to_file(ex.backtrace)
      terminate
    end

    def show_confirmation(message, default)
      exclusive do
        ask_confirm(message, default)
      end
    end

    def message_valid?(message)
      message[:type].present? && message[:type] == 'output' || message[:type] == 'event'
    end

    def show_terminal_screen(table)
      return unless table.rows.present?
      terminal_clear
      puts "\n"
      #  table.style = { width: 20 }
      puts table
      puts "\n"
      sleep(1)
      @job_manager.condition.signal('completed') if @manager.all_workers_finished?
    end

    def worker_state(worker, job)
      if worker.alive?
        state = worker.machine.state.to_s
        @manager.job_crashed?(job) ? state.red : state.green
      else
        'dead'.upcase.red
      end
    end


    def get_worker_details(job_id, job,  worker)
      {
        'job_id' => job_id,
        'app_name' => job.app,
        'env_name' => job.stage,
        'full_stage' => job.job_stage,
        'action_name' => job.capistrano_action,
        'env_options' => job.setup_command_line_standard.join("\n"),
        'task_arguments' => job.task_arguments,
        'state' => worker_state(worker, job),
        'processed_job' => job
      }
    end

    def add_job_to_table(table, job_id, job, count, last_job_id)
      return unless @manager.alive?
      worker = @manager.get_worker_for_job(job_id)

      details = get_worker_details(job_id, job, worker)

      row = [{ value: count.to_s },
             { value: job_id.to_s },
             { value: details['full_stage'] },
             { value: details['action_name'] },
             { value: details['env_options'] },
             { value: "#{details['state']}" }
            ]

      #   if  worker.alive?
      #     row << { value: worker.rake_tasks.size }
      #     row << { value: worker_progress(details['processed_job'], worker) }
      #   else
      #     row << { value: 0 }
      #     row << { value:  worker_state(worker) }
      #   end
      table.add_row(row)
      table.add_separator if last_job_id != job_id.to_i
    end

    def terminal_clear
      system('cls') || system('clear') || puts("\e[H\e[2J")
    end

    def worker_progress(processed_job, worker)
      return worker_state(worker) unless worker.alive?
      tasks = worker.alive? ? worker.invocation_chain : []
      current_task = worker.alive? ? worker.machine.state.to_s : ''
      show_worker_percent(worker, tasks, current_task, processed_job)
    end

    def show_worker_percent(worker, tasks, current_task, processed_job)
      total_tasks = worker.alive? ? tasks.size : nil
      task_index = worker.alive? ? tasks.index(current_task.to_s).to_i + 1 : 0
      percent = percent_of(task_index, total_tasks)
      result  = "Progress [#{format('%.2f', percent)}%]  (executed #{task_index} of #{total_tasks})"
      if worker.alive?
          @manager.job_crashed?(processed_job) ? result.red : result.green
      else
        worker_state(worker)
      end
    end

    def percent_of(index, total)
      index.to_f / total.to_f * 100.0
    end
  end
end
