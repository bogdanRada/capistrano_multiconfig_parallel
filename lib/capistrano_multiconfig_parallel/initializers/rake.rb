require_relative '../classes/rake_task_hooks'
Rake::Task.class_eval do
  alias_method :original_execute, :execute

  def execute(*args)
    rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(ENV, self)
    rake.automatic_hooks do
      original_execute(*args)
    end
  end
end
