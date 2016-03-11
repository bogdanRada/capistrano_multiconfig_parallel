require_relative '../classes/rake_task_hooks'
if defined?(Rake::Task)
  Rake::Task.class_eval do
    alias_method :original_execute, :execute

    def execute(*args)
      rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(self)
      rake.automatic_hooks do
        original_execute(*args)
      end
    end
  end
end
