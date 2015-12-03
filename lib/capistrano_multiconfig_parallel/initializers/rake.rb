require_relative '../classes/rake_hook_actor'
Rake::Task.class_eval do
  alias_method :original_execute, :execute

  def execute(*args)
    rake = CapistranoMulticonfigParallel::RakeHookActor.new(ENV, self)
    rake.work do
      original_execute(*args)
    end
  end
end
