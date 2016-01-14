module CapistranoMulticonfigParallel
  # module used to fetch the stages (code taken from https://github.com/railsware/capistrano-multiconfig)
  # TODO: find a way to remove this and still be compatible with capistrano 2.x
  module StagesHelper
  module_function

    def stages(path = nil)
      path.blank? && independent_deploy? ? fetch_stages_from_file : fetch_stages_app(path)
    end

    def multi_apps?(path = nil)
      path.blank? && independent_deploy? ? true : stages(path).find { |stage| stage.include?(':') }.present?
    end

    def fetch_stages_from_file
      configuration.application_dependencies.map { |hash| hash[:app] }
    end

    def app_names_from_stages
      independent_deploy? ? fetch_stages_from_file : stages.map { |stage| stage.split(':').reverse[1] }.uniq
    end

    def independent_deploy?
      app_with_no_path = configuration.application_dependencies.find { |hash| hash[:path].blank? }
      configuration.config_dir.present? && app_with_no_path.blank? ? true : false
    end

    def fetch_stages_app(path)
      fetch_stages_paths(path) do |paths|
        checks_paths(paths)
      end
    end

    def checks_paths(paths)
      paths.reject! { |path| check_stage_path(paths, path) }
      sorted_paths(paths)
    end

    def sorted_paths(paths)
      paths.present? ? paths.uniq.sort : paths
    end

    def check_stage_path(paths, path)
      paths.any? { |another| another != path && another.start_with?(path + ':') }
    end

    def stages_root(path)
      File.expand_path(File.join(path || detect_root, 'config/deploy'))
    end

    def stages_paths(path)
      root_stages = stages_root(path)
      Dir["#{root_stages}/**/*.rb"].map do |file|
        file.slice(root_stages.size + 1..-4).tr('/', ':')
      end
    end

    def fetch_stages_paths(path)
      stages_paths(path).tap { |paths| yield paths if block_given? }
    end
  end
end
