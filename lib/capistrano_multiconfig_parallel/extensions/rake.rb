require_relative './extension_helper'
Rake::Task.class_eval do
  alias_method :original_execute, :execute

  def execute(*args)
    if CapistranoMulticonfigParallel::ExtensionHelper.inside_job?
      CapistranoMulticonfigParallel::ExtensionHelper.run_the_actor(self) do
        original_execute(*args)
     end
    else
      original_execute(*args)
    end
  end
end
