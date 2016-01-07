module CapistranoMulticonfigParallel
  # helper used to determine gem versions
  module GemHelper
  module_function

    def find_loaded_gem(name)
      Gem.loaded_specs.values.find { |repo| repo.name == name }
    end

    def find_loaded_gem_property(gem_name, property = 'version')
      gem_spec = find_loaded_gem(gem_name)
      gem_spec.respond_to?(property) ? gem_spec.send(property) : nil
    end

    def fetch_gem_version(gem_name)
      version = find_loaded_gem_property(gem_name)
      version.blank? ? nil : get_parsed_version(version)
    end

    def get_parsed_version(version)
      version = version.to_s.split('.')
      version.pop until version.size == 2
      version.join('.').to_f
    end

    def verify_gem_version(gem_name, version, options = {})
      options.stringify_keys!
      version = get_parsed_version(version)
      gem_version = fetch_gem_version(gem_name)
      gem_version.blank? ? false : gem_version.send(options.fetch('operator', '<='), version)
    end
  end
end
