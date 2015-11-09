# Returns the version of the currently loaded gem as a <tt>Gem::Version</tt>
module CapistranoMulticonfigParallel
  def self.gem_version
    Gem::Version.new VERSION::STRING
  end

  # module used for generating the version
  module VERSION
    MAJOR = 0
    MINOR = 12
    TINY = 3
    PRE = nil

    STRING = [MAJOR, MINOR, TINY, PRE].compact.join('.')
  end
end
