module Bundler
  module UI
    class Shell
      alias_method :original_tell_me, :tell_me

      def tell_me(msg, color = nil, newline = nil)
        rake = CapistranoSentinel::RequestHooks.new(msg)
        rake.show_bundler_progress do
          original_tell_me(msg, color, newline)
        end
      end

    end
  end

  class << self

    def root=(path)
      @root = path
    end

  end

end
