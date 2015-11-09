require 'open3'
module CapistranoMulticonfigParallel
  # class used to display the progress of each worker on terminal screen using a table
  # rubocop:disable ClassLength
  class TerminalTable
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Logger
    TOPIC = 'sshkit_terminal'

    def initialize(manager, job_manager)
      @manager = manager
      @job_manager = job_manager
      async.run
    end

    def run
      subscribe(CapistranoMulticonfigParallel::TerminalTable::TOPIC, :notify_time_change)
    end

    def notify_time_change(topic, message)
      return unless topic == CapistranoMulticonfigParallel::TerminalTable::TOPIC
      default_headings = ['Job ID', 'App/Stage', 'Action', 'ENV Variables', 'Current Task']
      # if CapistranoMulticonfigParallel.show_task_progress
      #   default_headings << 'Total'
      #   default_headings << 'Progress'
      # end
      table = Terminal::Table.new(title: 'Deployment Status Table', headings: default_headings)
      if @manager.jobs.present? && message_valid?(message)
        @manager.jobs.each do |job_id, _job|
          add_job_to_table(table, job_id)
        end
      end
      show_terminal_screen(table)
    rescue => ex
      info "Terminal Table  client disconnected due to error #{ex.inspect}"
      info ex.backtrace
      terminate
    end

    def show_confirmation(message, default)
      exclusive do
        CapistranoMulticonfigParallel.ask_confirm(message, default)
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

    def worker_state(worker)
      if worker.alive?
        state = worker.machine.state.to_s
        worker.crashed? ? state.red : state.green
      else
        'dead'.upcase.red
      end
    end

    def worker_env_options(processed_job)
      worker_optons = ''
      processed_job['job_argv'].each do |elem|
        worker_optons << "#{elem}\n"
      end
      worker_optons
    end

    def worker_action(processed_job)
      processed_job['task_arguments'].present? ? "#{processed_job['action_name']}[#{processed_job['task_arguments'].join(',')}]" : processed_job['action_name']
    end

    def worker_stage(processed_job)
      processed_job['app_name'].present? ? "#{processed_job['app_name']}\n#{processed_job['env_name']}" : "#{processed_job['env_name']}"
    end

    def get_worker_details(job_id, worker)
      job = @manager.jobs[job_id]
      processed_job = @manager.process_job(job)

      {
        'job_id' => job_id,
        'app_name' => processed_job['app_name'],
        'env_name' => processed_job['env_name'],
        'full_stage' => worker_stage(processed_job),
        'action_name' => worker_action(processed_job),
        'env_options' => worker_env_options(processed_job),
        'task_arguments' => job['task_arguments'],
        'state' => worker_state(worker)
      }
    end

    def add_job_to_table(table, job_id)
      worker = @manager.get_worker_for_job(job_id)
      details = get_worker_details(job_id, worker)

      row = [{ value: job_id.to_s },
             { value: details['full_stage'] },
             { value: details['action_name'] },
             { value: details['env_options'] },
             { value: "#{details['state']}" }
            ]
      # if CapistranoMulticonfigParallel.show_task_progress
      #   if  worker.alive?
      #     row << { value: worker.rake_tasks.size }
      #     row << { value: worker_progress(details, worker) }
      #   else
      #     row << { value: 0 }
      #     row << { value:  worker_state(worker) }
      #   end
      # end
      table.add_row(row)
      table.add_separator if @manager.jobs.keys.last.to_i != job_id.to_i
    end

    def terminal_clear
      system('cls') || system('clear') || puts("\e[H\e[2J")
    end

    def worker_dry_running?(worker)
      worker.alive? && worker.dry_running?
    end

    def worker_progress(_details, worker)
      return worker_state(worker) unless worker.alive?
      return if worker.executing_dry_run.nil?
      tasks = worker.alive? ? worker.dry_run_tasks : []
      current_task = worker.alive? ? worker.machine.state.to_s : ''
      total_tasks = worker_dry_running?(worker) ? nil : tasks.size
      task_index = worker_dry_running?(worker) ? 0 : tasks.index(current_task.to_s).to_i + 1
      percent = percent_of(task_index, total_tasks)
      result  = worker_dry_running?(worker) ? 'Please wait.. building the progress bars' : "Progress [#{sprintf('%.2f', percent)}%]  (executed #{task_index} of #{total_tasks})"
      if worker.alive?
        worker.crashed? ? result.red : result.green
      else
        worker_state(worker)
      end
    end

    def percent_of(index, total)
      index.to_f / total.to_f * 100.0
    end
  end
end
