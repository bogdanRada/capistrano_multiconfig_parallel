
module CapistranoMulticonfigParallel
  # class used to display the progress of each worker on terminal screen using a table
  # rubocop:disable ClassLength
  class TerminalTable
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Logger
    TOPIC = 'sshkit_terminal'

    def initialize(manager)
      @manager = manager
      async.run
    end

    def run
      subscribe(CapistranoMulticonfigParallel::TerminalTable::TOPIC, :notify_time_change)
    end

    def notify_time_change(topic, message)
      return unless topic == CapistranoMulticonfigParallel::TerminalTable::TOPIC
      default_headings = ['Job ID', 'App/Stage', 'Action', 'ENV Variables', 'Current Task']
      if CapistranoMulticonfigParallel.show_task_progress
        default_headings << 'Total'
        default_headings << 'Progress'
      end
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
    end
    
    def get_worker_details(job_id)
      job = @manager.jobs[job_id]
      processed_job = @manager.process_job(job)
      worker = @manager.get_worker_for_job(job_id)
      if worker.alive?
        state = worker.machine.state.to_s
        state = worker_crashed?(worker) ? state.red : state.green
      else
        state = "dead".upcase.red
      end
      worker_optons = ''
      processed_job['env_options'].each do |key, value|
        worker_optons << "#{key}=#{value}\n"
      end
      action = processed_job['task_arguments'].present? ? "#{processed_job['action_name']}[#{processed_job['task_arguments'].join(',')}]" :  processed_job['action_name']
      
      {
        'job_id' => job_id,
        'app_name' =>processed_job['app_name'],
        'env_name' =>processed_job['env_name'],
        'action_name' => action,
        'env_options' => worker_optons,
        'task_arguments' => job['task_arguments'],
        'state' =>  state
      }
    end
    
    def add_job_to_table(table, job_id)
      details = get_worker_details(job_id)
      row = [{ value: job_id.to_s },
        { value: "#{details['app_name']}\n#{details['env_name']}" },
        { value: details['action_name']  },
        { value: details['env_options'] },
        { value: "#{details['state']}" }
      ]
      if CapistranoMulticonfigParallel.show_task_progress
        row << { value: worker.rake_tasks.size }
        row << { value: worker_progress(worker) }
      end
      table.add_row(row)
      table.add_separator if @manager.jobs.keys.last.to_i != job_id.to_i
    end

    def terminal_clear
      system('cls') || system('clear') || puts("\e[H\e[2J")
    end

    def worker_crashed?(worker)
      worker.crashed?
    end
    # rubocop:disable Lint/Eval
    def capture(stream)
      stream = stream.to_s
      captured_stream = Tempfile.new(stream)
      stream_io = eval("$#{stream}")
      origin_stream = stream_io.dup
      stream_io.reopen(captured_stream)

      yield

      stream_io.rewind
      return captured_stream.read
    ensure
      captured_stream.close
      captured_stream.unlink
      stream_io.reopen(origin_stream)
    end

    def worker_progress(worker)
      tasks = worker.rake_tasks
      current_task = worker.machine.state
      total_tasks = tasks.size
      task_index = tasks.index(current_task)
      progress = Formatador::ProgressBar.new(total_tasks, color: 'green', start: task_index.to_i)
      result = capture(:stdout) do
        progress.increment
      end
      result = result.gsub("\r\n", '')
      result = result.gsub("\n", '')
      result = result.gsub('|', '#')
      result = result.gsub(/\s+/, ' ')
      if worker_crashed?(worker)
        return result.red
      else
        return result.green
      end
    end
  end
end
