module Bundler
  module UI
    class Shell
      alias_method :original_tell_me, :tell_me

      def tell_me(msg, color = nil, newline = nil)
        rake = CapistranoMulticonfigParallel::RakeTaskHooks.new(msg)
        rake.show_bundler_progress do
          original_tell_me(msg, color, newline)
        end
      end

    end
  end
end
