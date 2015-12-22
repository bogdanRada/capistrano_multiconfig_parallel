
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

    def default_heaadings
      ['Job ID', 'Job UUID', 'App/Stage', 'Action', 'ENV Variables', 'Current Task']
    end

    def run
      subscribe(CapistranoMulticonfigParallel::TerminalTable.topic, :notify_time_change)
    end

    def notify_time_change(_channel, _message)
      table = Terminal::Table.new(title: 'Deployment Status Table', headings: default_heaadings)
      setup_table_jobs(table)
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

    def setup_table_jobs(table)
      jobs = @manager.alive? ? @manager.jobs.dup : []
      jobs.each do |_job_id, job|
        table.add_row(job.terminal_row)
        table.add_separator
      end
    end

    def show_confirmation(message, default)
      exclusive do
        ask_confirm(message, default)
      end
    end

    def managers_alive?
      @job_manager.alive? && @manager.alive?
    end

    def signal_complete
      if managers_alive? && @manager.all_workers_finished?
        @job_manager.condition.signal('completed')
      elsif !managers_alive?
        terminate
      end
    end

    def terminal_clear
      system('cls') || system('clear') || puts("\e[H\e[2J")
    end
  end
end
