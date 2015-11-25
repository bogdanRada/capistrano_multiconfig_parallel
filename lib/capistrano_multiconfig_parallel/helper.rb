# module used for feching gem information
module Helper
# function that makes the methods incapsulated as utility functions

module_function

  def find_loaded_gem_property(gem_name, property)
    gem_spec = Gem.loaded_specs.values.find { |repo| repo.name == gem_name }
    gem_spec.respond_to?(property) ? gem_spec.send(property) : nil
  end

  def fetch_gem_version(gem_name, options = {})
    version = find_loaded_gem_property(gem_name, 'version')
    version.blank? ? nil : get_parsed_version(version.to_s, options)
  end

  def get_parsed_version(version, options)
    parsing_options = { optional_fields: [:tiny] }.merge(options.fetch('unparse', {}))
    Versionomy.parse(version).unparse(parsing_options)
  rescue Versionomy::Errors::ParseError
    nil
  end

  def verify_gem_version(gem_name, version, options = {})
    options.stringify_keys!
    version = get_parsed_version(version, options)
    gem_version = fetch_gem_version(gem_name, options)
    gem_version.blank? ? false : gem_version.send(options.fetch('operator', '<='), version)
  end
end
