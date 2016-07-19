require_relative './runner_status'
module CapistranoMulticonfigParallel
  # class that is used to execute the capistrano tasks and it is invoked by the celluloid worker
  class ChildProcessStatus < CapistranoMulticonfigParallel::RunnerStatus

    attr_accessor :show_bundler

    def initialize(process_runner, job, command, options={})
      super(process_runner, job, command, options)
      @show_bundler = true
    end

    def print_error_if_exist
      return unless development_debug?
      [@job.stderr_buffer].each do |buffer|
        buffer.rewind
        data = buffer.read
        log_output_error(nil, 'stderr', "Child process for worker #{@job_id} died for reason: #{data}") if data.present?
      end
    end

    def on_input_stdin(data)
      io_callback('stdin', data)
    end

    def on_read_stdout(data)
      @show_bundler = false if  data.to_s.include?("The Gemfile's dependencies are satisfied") || data.to_s.include?("Bundle complete")
      @actor.async.update_machine_state(truncate(data, 40), :bundler => true) if @show_bundler == true && data.strip.present? && data.strip != '.'
      io_callback('stdout', data)
    end

    def on_read_stderr(data)
      @job.save_stderr_error(data) if development_debug?
      io_callback('stderr', data)
    end

    def on_timeout
      log_to_file "Child process for worker #{@job_id} on_timeout  disconnected"
      @did_timeout = true
      @callback.call(self) if @expect_timeout
    end

    def on_size_limit
      log_to_file "Child process for worker #{@job_id} on_size_limit  disconnected"
      @did_size_limit = true
      @callback.call(self) if @expect_size_limit
    end

    def on_exit(status)
      log_to_file "Child process for worker #{@job_id} on_exit  disconnected due to error #{exit_status.inspect}"
      print_error_if_exist
      @exit_status = status.exitstatus
    end

    def async_exception_handler(*data)
      log_to_file "Child process for worker #{@job_id} async_exception_handler  disconnected due to error #{data.inspect}"
      io_callback('stderr', data)
      @exit_status = 1
    end

    def watch_handler(process)
      @process ||= process
    end

    def io_callback(io, data)
      log_to_worker(data, io)
    end
  end
end
