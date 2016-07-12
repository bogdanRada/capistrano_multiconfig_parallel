
require_relative '../helpers/base_actor_helper'
module CapistranoMulticonfigParallel
  # class used to display the progress of each worker on terminal screen using a table
  class TerminalTable
  include CapistranoMulticonfigParallel::BaseActorHelper

    attr_reader :options, :errors, :manager, :position, :job_manager, :terminal_rows, :screen_erased

    delegate :workers_terminated,
             to: :manager

    delegate :condition,
             to: :job_manager

    def self.topic
      'sshkit_terminal'
    end

    def initialize(manager, job_manager, options = {})
      @manager = manager
      @position = nil
      @terminal_rows = nil
      @cursor = CapistranoMulticonfigParallel::Cursor.new
      @errors = []
      @options = options.is_a?(Hash) ? options.stringify_keys : options
      @job_manager = job_manager
      @screen_erased = false
      async.run
    rescue => ex
      rescue_exception(ex)
    end

    def default_heaadings
      ['Job UUID', 'App/Stage', 'Action', 'ENV Variables', 'Current Status']
    end

    def run
      subscribe(CapistranoMulticonfigParallel::TerminalTable.topic, :notify_time_change)
    end

    def notify_time_change(_channel, _message)
      table = Terminal::Table.new(title: 'Deployment Status Table', headings: default_heaadings)
      jobs = setup_table_jobs(table)
      display_table_on_terminal(table, jobs)
    end

    def rescue_exception(ex)
      log_to_file("Terminal Table client disconnected due to error #{ex.inspect}")
      rescue_error(ex, 'stderr')
      terminate
    end

    def fetch_table_size(jobs)
      job_rows = jobs.sum { |_job_id, job| job.row_size }
      (job_rows + 2)**2
    end

    def display_table_on_terminal(table, jobs)
      table_size = fetch_table_size(jobs)
      @position, @terminal_rows, @screen_erased = @cursor.display_on_screen(
        "#{table}",
        @options.merge(
          position: @position,
          table_size: table_size,
          screen_erased: @screen_erased
        )
      )
      print_errors
      signal_complete
    end

    def print_errors
      puts(@errors.join("\n")) if @errors.present? && @options.fetch('clear_screen', false).to_s == 'false' && development_debug?
    end

    def setup_table_jobs(table)
      jobs = managers_alive? ? @manager.jobs.dup : []
      jobs.each do |job_id, job|
        table.add_row(job.terminal_row)
        table.add_separator if jobs.keys.last != job_id
      end
      jobs
    end

    def show_confirmation(message, default)
      exclusive do
        ask_confirm(message, default)
      end
    end

    def managers_alive?
       @manager.alive?
    end

    def signal_complete
      if managers_alive? && @manager.all_workers_finished? && workers_terminated.instance_variable_get("@waiters").blank?
        condition.signal('completed') if condition.instance_variable_get("@waiters").present?
      elsif !managers_alive?
        terminate
      end
    end
  end
end
