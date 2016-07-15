require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  class RunnerStatus
    include CapistranoMulticonfigParallel::ApplicationHelper

    ATTRIBUTE_LIST = [
      :job,
      :process_runner,
      :command,
      :options,
      :actor,
      :job_id,
      :output_text,
      :error_text,
      :exit_status,
      :did_timeout,
      :callback,
      :pid,
      :force_yield,
      :expect_timeout,
      :expect_size_limit,
      :async_exception,
      :process
    ]

    attr_reader *CapistranoMulticonfigParallel::RunnerStatus::ATTRIBUTE_LIST
    attr_accessor *CapistranoMulticonfigParallel::RunnerStatus::ATTRIBUTE_LIST

    def initialize(process_runner, job, command, options={})
      options = options.is_a?(Hash) ? options : {}
      @job = job
      @process_runner = process_runner
      @command     = command
      @options = {:repeats=>1, :force_yield=>nil, :timeout=>nil, :expect_timeout=>false}.merge(options)
      @options = @options.symbolize_keys

      @actor = @options.fetch(:actor, nil)
      @job_id = @job.id
      @process_runner = process_runner


      @output_text = ""
      @error_text  = ""
      @exit_status      = nil
      @did_timeout = false
      @callback    = process_runner.callback
      @pid         = nil
      @force_yield = @options[:force_yield]

      @expect_timeout    = @options[:expect_timeout] || false
      @expect_size_limit = @options[:expect_size_limit] || false
      @async_exception   = nil
    end

    def on_pid(pid)
      @pid ||= pid
    end


    def on_input_stdin(*data)
        @output_text << data
    end

    def on_read_stdout(*data)
      sleep @force_yield if @force_yield
      @output_text << data
    end

    def on_read_stderr(*data)
      sleep @force_yield if @force_yield
      @error_text << data
    end


    def on_timeout
      puts "\n** Failed to run #{@command.inspect}: Timeout" unless @expect_timeout
      @did_timeout = true
      @callback.call(self) if @expect_timeout
    end

    def on_size_limit
      puts "\n** Failed to run #{@command.inspect}: Size limit" unless @expect_size_limit
      @did_size_limit = true
      @callback.call(self) if @expect_size_limit
    end

    def on_exit(status)
      log_to_file "Child process for worker #{@job_id} on_exit  disconnected due to error #{status.inspect}"
      @exit_status = status.exitstatus
      process_runner.check_exit_status
      @callback.call(self)
    end

    def async_exception_handler(*async_exception)
      @async_exception = async_exception
      log_to_file "Child process for worker #{@job_id} async_exception_handler  disconnected due to error #{data.inspect}"
      @exit_status = 1
      process_runner.check_exit_status
    end

    def watch_handler(process)
      @process ||= process
      process_runner.check_exit_status
    end


    def inspect
      to_s
    end

    def to_s
      JSON.generate(to_json)
    end

    def to_json
      hash = {}
      CapistranoMulticonfigParallel::RunnerStatus::ATTRIBUTE_LIST.delete_if{|a| [:process_runner].include?(a) }.each do |key|
        hash[key] = send(key).inspect
      end
      hash
    end

  end
end
