if CapistranoMulticonfigParallel.capistrano_version_2? == true
puts 'MULTI CAP 2'
  if defined?(HighLine)
    HighLine.class_eval do
      alias_method :original_ask, :ask

      def ask(question, answer_type = String, &details)
        rake = CapistranoMulticonfigParallel::RakeTaskHooks.new
        rake.print_question?(question) do
          original_ask(question, answer_type, &details)
        end
      end
    end
  end

  if defined?(Capistrano::Configuration::Execution)
    Capistrano::Configuration::Execution.class_eval do
      alias_method :original_execute_task, :execute_task

      def execute_task(task)
        rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(task)
        rake.automatic_hooks do
          original_execute_task(task)
        end
      end
    end
  end

  if defined?(Capistrano::Configuration::Callbacks)
    Capistrano::Configuration::Callbacks.class_eval do
      alias_method :original_trigger, :trigger

      def trigger(event, task = nil)
        rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(task)
        rake.automatic_hooks do
          original_trigger(event, task)
        end
      end
    end
  end
end
