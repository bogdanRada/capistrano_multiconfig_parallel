module CapistranoMulticonfigParallel
  # module used to fetch the stages (code taken from https://github.com/railsware/capistrano-multiconfig)
  # TODO: find a way to remove this and still be compatible with capistrano 2.x
  module StagesHelper
  module_function

    def stages
      fetch_stages_paths do |paths|
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

    def stages_paths
      stages_root = File.expand_path(File.join(detect_root, 'config/deploy'))
      Dir["#{stages_root}/**/*.rb"].map do |file|
        file.slice(stages_root.size + 1..-4).tr('/', ':')
      end
    end

    def fetch_stages_paths
      stages_paths.tap { |paths| yield paths if block_given? }
    end
  end
end
