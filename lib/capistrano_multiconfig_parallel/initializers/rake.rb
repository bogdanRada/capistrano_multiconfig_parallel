require_relative '../classes/rake_task_hooks'
Rake::Task.class_eval do
  alias_method :original_execute, :execute
  alias_method :original_enhance, :enhance

  def enhance(deps = nil, &block)
    CapistranoMulticonfigParallel::RakeTaskHooks.new(ENV, self).rake_task_list.register_hooks(deps, &block)
    original_enhance(deps, &block)
  end

  def execute(*args)
    rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(ENV, self)
    rake.automatic_hooks do
      original_execute(*args)
    end
  end
end
