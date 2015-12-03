module CapistranoMulticonfigParallel
  # module used to fetch the stages (code taken from https://github.com/railsware/capistrano-multiconfig)
  # TODO: find a way to do this without copying code. Can't currently use gem specification to require that gem
  # because that is only compatible with capistrano version 3
  module StagesHelper
  module_function

    def fetch_stages
      fetch_stages_paths do |paths|
        checks_paths(paths)
      end
    end

    def checks_paths(paths)
      paths.reject! { |path| check_stage_path(paths, path) }.uniq.sort
    end

    def check_stage_path(paths, path)
      paths.any? { |another| another != path && another.start_with?(path + ':') }
    end

    def stages_paths
      stages_root = 'config/deploy'
      Dir["#{stages_root}/**/*.rb"].map do |file|
        file.slice(stages_root.size + 1..-4).tr('/', ':')
      end
    end

    def fetch_stages_paths
      stages_paths.tap { |paths| yield paths if block_given? }
    end
  end
end
