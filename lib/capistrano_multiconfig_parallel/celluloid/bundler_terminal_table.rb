module CapistranoMulticonfigParallel
  class BundlerTerminalTable < CapistranoMulticonfigParallel::TerminalTable

    def self.topic
      'bundler_terminal'
    end

    def default_heaadings
      ['Job UUID', 'App', 'Action', 'Current Status']
    end

    def run
      subscribe(CapistranoMulticonfigParallel::BundlerTerminalTable.topic, :notify_bundler_install_status)
    end

    def notify_bundler_install_status(_channel, _message)
      table = Terminal::Table.new(title: 'Bundler Check Status Table', headings: default_heaadings)
      jobs = setup_table_jobs(table)
      display_table_on_terminal(table, jobs)
    end

    def fetch_table_size(jobs)
      job_rows = jobs.sum { |job, _bundler_worker| job.row_size }
      (job_rows + 2)**2
    end


    def setup_table_jobs(table)
      jobs = managers_alive? ? @job_manager.bundler_workers_store.dup : []
      jobs.each do |job, bundler_worker|
        table.add_row(job.bundler_check_terminal_row)
        table.add_separator if jobs.keys.last != job
      end
      jobs
    end

    def managers_alive?
      @job_manager.alive?
    end

  end
end
