module CapistranoMulticonfigParallel
  class RunnerStatus
    def initialize(command, options={}, &callback)
      options = {:repeats=>1, :force_yield=>nil, :timeout=>nil, :expect_timeout=>false}.merge(options)

      @command     = command
      @output_text = ""
      @error_text  = ""
      @status      = nil
      @did_timeout = false
      @callback    = callback
      @pid         = nil
      @force_yield = options[:force_yield]

      @expect_timeout    = options[:expect_timeout]
      @expect_size_limit = options[:expect_size_limit]
      @async_exception   = nil
    end

    attr_accessor :output_text, :error_text, :status, :pid
    attr_accessor :did_timeout, :did_size_limit, :async_exception

    def on_read_stdout(data)
      sleep @force_yield if @force_yield
      @output_text << data
    end

    def on_read_stderr(data)
      sleep @force_yield if @force_yield
      @error_text << data
    end

    def on_pid(pid)
      raise "PID already set!" unless @pid.nil?
      @pid = pid
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
      @status = status
      @callback.call(self)
    end

    def on_async_exception(async_exception)
      @async_exception = async_exception
    end
  end
end
