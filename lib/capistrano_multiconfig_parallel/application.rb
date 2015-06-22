module CapistranoMulticonfigParallel
  # class used as a wrapper around capistrano
  class Application < Capistrano::Application
    def name
      'multi_cap'
    end

    def sort_options(options)
      super.push(multi_debug, multi_progress, multi_secvential)
    end

    def multi_debug
      ['--multi-debug', '-D',
       'Sets the debug enabled for celluloid actors',
       lambda do |_value|
         CapistranoMulticonfigParallel::CelluloidManager.debug_enabled = true
         Celluloid.task_class = Celluloid::TaskThread
       end
      ]
    end

    def multi_progress
      ['--multi-progress', '--multi-progress',
       'Sets the debug enabled for celluloid actors',
       lambda do |_value|
         CapistranoMulticonfigParallel.show_task_progress = true
       end
      ]
    end

    def multi_secvential
      ['--multi-secvential', '--multi-secvential',
       'Sets the debug enabled for celluloid actors',
       lambda do |_value|
         CapistranoMulticonfigParallel.execute_in_sequence = true
       end
      ]
    end

    def top_level
      job_manager = multi_manager_class.new(self, top_level_tasks, stages)
      if job_manager.can_start? && !options.show_prereqs && !options.show_tasks
        job_manager.start
      else
        super
      end
    end

    def multi_apps?
      stages.find { |stage| stage.include?(':') }.present?
    end

    def multi_manager_class
      multi_apps? ? CapistranoMulticonfigParallel::MultiAppManager : CapistranoMulticonfigParallel::SingleAppManager
    end
  end
end
