module CapistranoMulticonfigParallel
  # class used as a wrapper around capistrano
  class Application < Capistrano::Application
    def name
      'multi_cap'
    end

    def sort_options(options)
      super.concat(CapistranoMulticonfigParallel.capistrano_options)
    end

    def top_level
      job_manager = CapistranoMulticonfigParallel::BaseManager.new
      if job_manager.can_start? && !options.show_prereqs && !options.show_tasks
        job_manager.start
      else
        super
      end
    end
  end
end
