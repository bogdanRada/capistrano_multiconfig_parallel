# Returns the version of the currently loaded gem as a <tt>Gem::Version</tt>
module CapistranoMulticonfigParallel
  def self.gem_version
    Gem::Version.new VERSION::STRING
  end

  # module used for generating the version
  module VERSION

    MAJOR = 2
    MINOR = 8
    TINY = 1
    PRE = nil

    STRING = [MAJOR, MINOR, TINY, PRE].compact.join('.')
  end
end
