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
      @callback    = @options[:callback].present? ? @options[:callback] : nil
      @pid         = nil
      @force_yield = @options[:force_yield]

      @expect_timeout    = @options[:expect_timeout] || false
      @expect_size_limit = @options[:expect_size_limit] || false
      @async_exception   = nil
    end

    def log_to_worker(message, io = nil)
      if io.present?
        log_to_file("#{io.upcase} ---- #{message}", job_id: @job_id, prefix: @options[:log_prefix])
      elsif @options[:log_prefix].present?
        log_to_file(message, job_id: @job_id, prefix: @options[:log_prefix])
      else
        log_to_file(message)
      end
    end

    def on_pid(pid)
      log_to_worker"Child process for worker #{@job_id} on_pid  #{pid.inspect}"
      @pid ||= pid
    end


    def on_input_stdin(data)
      log_to_worker(data, "stdin")
      @output_text << data
    end

    def on_read_stdout(data)
      log_to_worker(data, "stdout")
      @output_text << data
    end

    def on_read_stderr(data)
      log_to_worker(data, "stderr")
      @error_text << data
    end


    def on_timeout
      log_to_worker "Child process for worker #{@job_id} on_timeout  disconnected"
      @did_timeout = true
      @callback.call(self) if @callback && process_runner.synchronicity == :sync && @expect_timeout
    end

    def on_size_limit
      log_to_worker "Child process for worker #{@job_id} on_size_limit  disconnected"
      @did_size_limit = true
      @callback.call(self) if @callback && process_runner.synchronicity == :sync && @expect_size_limit
    end

    def on_exit(status)
      log_to_worker "Child process for worker #{@job_id} on_exit  disconnected due to #{status.inspect}"
      @exit_status = status.exitstatus
      @callback.call(self) if @callback && process_runner.synchronicity == :sync
    end

    def async_exception_handler(async_exception)
      @async_exception = async_exception
      log_to_worker "Child process for worker #{@job_id} async_exception_handler  disconnected due to error #{data.inspect}"
      @exit_status = 1
    end

    def watch_handler(process)
      @process ||= process
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
