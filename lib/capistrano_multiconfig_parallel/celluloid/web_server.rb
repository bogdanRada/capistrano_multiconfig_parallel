module CapistranoMulticonfigParallel
  # rubocop:disable ClassLength
  class WebServer  < CelluloidPubsub::WebServer

    def initialize(*args)
      super(*args)
    rescue
      #fails silently
    end
  end
end
