
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
    rescue => ex
      rescue_exception(ex)
    end

    def run
      subscribe(CapistranoMulticonfigParallel::TerminalTable.topic, :notify_time_change)
    end

    def notify_time_change(_topic, _message)
      table = Terminal::Table.new(title: 'Deployment Status Table', headings: ['Job ID', 'Job UUID', 'App/Stage', 'Action', 'ENV Variables', 'Current Task'])
      jobs = @manager.alive? ? @manager.jobs : []
      setup_table_jobs(table, jobs)
      display_table_on_terminal(table)
    end

    def rescue_exception(ex)
      log_to_file("Terminal Table client disconnected due to error #{ex.inspect}")
      log_error(ex, 'stderr')
      terminate
    end

    def display_table_on_terminal(table)
      terminal_clear
      puts "\n#{table}\n"
      signal_complete
    end

    def setup_table_jobs(table, jobs)
      jobs.each_with_index do |(_job_id, job), count|
        add_job_to_table(table, job, count)
        table.add_separator
      end
    end

    def show_confirmation(message, default)
      exclusive do
        ask_confirm(message, default)
      end
    end

    def signal_complete
      return if !@job_manager.alive? || @manager.alive?
      @job_manager.condition.signal('completed') if @manager.all_workers_finished?
    end

    def worker_state(job)
      default = job.status.to_s.upcase.red
      return default unless @manager.alive?
      worker = @manager.get_worker_for_job(job.id)
      worker.alive? ? worker.worker_state : default
    end

    def add_job_to_table(table, job, index)
      job_state = worker_state(job)
      job_row = job.terminal_row(index, job_state)
      table.add_row(job_row)
    end

    def terminal_clear
      system('cls') || system('clear') || puts("\e[H\e[2J")
    end
  end
end
