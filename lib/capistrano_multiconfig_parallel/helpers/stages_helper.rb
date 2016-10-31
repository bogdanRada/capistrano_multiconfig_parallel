# frozen_string_literal: true
module CapistranoMulticonfigParallel
  # module used to fetch the stages (code taken from https://github.com/railsware/capistrano-multiconfig)
  # but refactored to be able to detect stages from multiple paths
  module StagesHelper
  module_function

    def stages(path = nil)
      stages = path.present? ? fetch_stages_app(path) : []
      if path.blank?
        root = begin
                  detect_root
                rescue
                  nil
                end
        if root.present?
          stages = stages.concat(fetch_stages_app(nil))
        end
      end
      stages
    end

    def multi_apps?(path = nil)
      independent_deploy?(path) ? true : stages(path).find { |stage| stage.include?(':') }.present?
    end

    def application_supports_multi_apps?(path = nil)
      fetch_stages_app(path).find { |stage| stage.include?(':') }.present?
    end

    def fetch_apps_from_file
      configuration.application_dependencies.map { |hash| hash[:app] }
    end

    def app_names_from_stages
      app_names = fetch_apps_from_file
      new_apps = stages.map { |stage| stage.split(':').reverse[1] }.compact
      app_names.concat(new_apps).uniq
      app_names
    end

    def configuration_has_valid_path?(hash)
      hash[:path].present? && File.directory?(hash[:path])
    end

    def fetch_paths_from_file
      configuration.application_dependencies.select { |hash| configuration_has_valid_path?(hash) }.map { |hash| hash[:path] }
    end

    def independent_deploy?(path = nil)
      app_with_path = configuration.application_dependencies.find { |hash| configuration_has_valid_path?(hash).present? }
      configuration.config_dir.present? && app_with_path.present? && (path.nil? || (path.present? && fetch_paths_from_file.include?(path))) ? true : false
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
