
require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to display the progress of each worker on terminal screen using a table
  class TerminalTable
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Logger
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :options, :errors, :manager, :position, :job_manager

    def self.topic
      'sshkit_terminal'
    end

    def initialize(manager, job_manager, options = {})
      @manager = manager
      @position = nil
      @errors = []
      @options = options.is_a?(Hash) ? options.stringify_keys : options
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

    def fetch_cursor_position
      terminal_size = CapistranoMulticonfigParallel::Cursor.fetch_terminal_size
      @position ||= CapistranoMulticonfigParallel::Cursor.fetch_position
      return @position if terminal_size[:rows].nonzero? && position[:row] < (terminal_size[:rows] / 2)
      CapistranoMulticonfigParallel::Cursor.move_to_home!(0,0)
      @position = CapistranoMulticonfigParallel::Cursor.fetch_position
      @position
    end

    def display_table_on_terminal(table)
      cursor_position = fetch_cursor_position
      CapistranoMulticonfigParallel::Cursor.display_on_screen("\n#{table}\n", @options.merge(position: @position))
      puts(@errors.join("\n")) if @errors.present? && @options.fetch('clear_screen', false).to_s == 'false'
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
        @job_manager.condition.signal('completed') if @job_manager.alive?
      elsif !managers_alive?
        terminate
      end
    end

  end
end
