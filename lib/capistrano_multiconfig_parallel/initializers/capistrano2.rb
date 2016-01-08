if CapistranoMulticonfigParallel.capistrano_version_2?
  require 'capistrano/cli'

  HighLine.class_eval do
    alias_method :original_ask, :ask

    def ask(question, _answer_type = String, &_details)
      rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(ENV, nil, CapistranoMulticonfigParallel.original_args_hash)
      rake.actor.user_prompt_needed?(question)
    end
  end

  Capistrano::Configuration::Execution.class_eval do
    alias_method :original_execute_task, :execute_task

    def execute_task(task)
      rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(ENV, task, self)
      rake.automatic_hooks do
        original_execute_task(task)
      end
    end
  end

  Capistrano::Configuration::Callbacks.class_eval do
    alias_method :original_trigger, :trigger

    def trigger(event, task = nil)
      rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(ENV, task, self)
      rake.automatic_hooks do
        original_trigger(event, task)
      end
    end
  end

end
