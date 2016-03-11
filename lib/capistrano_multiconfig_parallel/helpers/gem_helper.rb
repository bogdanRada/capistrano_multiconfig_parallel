module CapistranoMulticonfigParallel
  # helper used to determine gem versions
  module GemHelper
    module_function

    def find_loaded_gem(name, property = nil)
      gem_spec = Gem.loaded_specs.values.find { |repo| repo.name == name }
      gem_spec.present? && property.present? ? gem_spec.send(property) : gem_spec
    end

    def find_gem_version_from_path(job_path = nil, name = 'capistrano')
      gem_path(name, job_path, "| grep  -Po  '#{name}-([0-9.]+)' | grep  -Po  '([0-9.]+)'")
    end

    def bundle_gemfile_env(job_path)
      "BUNDLE_GEMFILE=#{job_path}/Gemfile"
    end

    def gem_path(name, job_path = nil, grep = '')
      job_path = job_path.present? ? job_path : detect_root
      strip_characters_from_string(`cd #{job_path} && #{bundle_gemfile_env(job_path)} bundle show #{name} #{grep}`)
    end

    def find_loaded_gem_property(gem_name ='capistrano', property = 'version')
      job_path = CapistranoMulticonfigParallel.configuration[:job_path]
      if job_path.present?
        find_gem_version_from_path(job_path, gem_name)
      else
        find_loaded_gem(gem_name, property)
      end
    end

    def get_parsed_version(version)
      return 0 if version.blank?
      version = version.to_s.split('.')
      version = format_gem_version(version)
      version.join('.').to_f
    end

    def format_gem_version(version)
      return version if version.size <= 2
      version.pop until version.size == 2
      version
    end

    def verify_gem_version(gem_version, version, options = {})
      options.stringify_keys!
      version = get_parsed_version(version)
      get_parsed_version(gem_version).send(options.fetch('operator', '<='), version)
    end
  end
end
