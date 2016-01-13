module CapistranoMulticonfigParallel
  # helper used to determine gem versions
  module GemHelper
  module_function

    def find_loaded_gem(name, property = nil)
      gem_spec = Gem.loaded_specs.values.find { |repo| repo.name == name }
      property.present? ? gem_spec.send(property) : gem_spec
    end

    def find_loaded_gem_property(gem_name, property = 'version')
      find_loaded_gem(gem_name, property)
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

    def verify_gem_version(gem_version, version, options = {})
      version = get_parsed_version(version)
      get_parsed_version(gem_version).send(options.fetch('operator', '<='), version)
    end
  end
end
