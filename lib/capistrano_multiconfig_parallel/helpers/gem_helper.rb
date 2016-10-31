# frozen_string_literal: true
module CapistranoMulticonfigParallel
  # helper used to determine gem versions
  module GemHelper
  module_function

    def find_loaded_gem(name, property = nil)
      gem_spec = Gem.loaded_specs.values.find { |repo| repo.name == name }
      gem_spec.present? && property.present? ? gem_spec.send(property).to_s : gem_spec
    end

    def find_loaded_gem_property(gem_name, property = 'version')
      find_loaded_gem(gem_name, property)
    end

    def fetch_gem_version(gem_name)
      version = find_loaded_gem_property(gem_name)
      version.blank? ? nil : get_parsed_version(version)
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
