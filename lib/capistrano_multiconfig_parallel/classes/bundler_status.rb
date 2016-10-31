# frozen_string_literal: true
require_relative './runner_status'
module CapistranoMulticonfigParallel
  # class that is used to execute the capistrano tasks and it is invoked by the celluloid worker
  class BundlerStatus < CapistranoMulticonfigParallel::RunnerStatus
    def on_read_stdout(data)
      show_bundler_progress(data)
      super(data)
    end

    def show_bundler_progress(data)
      data = data.strip
      return if data.blank? || data == '.'
      if @actor.present? && @actor.respond_to?(:show_bundler_progress)
        call_bundler_progress(data)
      end
    end

    def call_bundler_progress(data)
      if @actor.respond_to?(:async)
        @actor.async.show_bundler_progress(data)
      else
        @actor.show_bundler_progress(data)
      end
    end
  end
end
