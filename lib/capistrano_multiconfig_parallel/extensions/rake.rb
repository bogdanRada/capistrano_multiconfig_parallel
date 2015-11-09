require_relative './extension_helper'
Rake::Task.class_eval do
  alias_method :original_execute, :execute

  def execute(*args)
    rake = CapistranoMulticonfigParallel::ExtensionHelper.new(ENV, self)
    rake.work do
      original_execute(*args)
    end
  end
end
