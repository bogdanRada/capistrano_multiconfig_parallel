module Helper

  module_function

  def find_loaded_gem(name)
    Gem.loaded_specs.values.detect{|repo| repo.name == name }
  end

end
