module CapistranoMulticonfigParallel
  # class used to start the web server for websockets
  class WebServer < CelluloidPubsub::WebServer
    def initialize(*args)
      super(*args)
    rescue => exc
      CapistranoMulticonfigParallel.log_message(exc)
      # fails silently
    end
  end
end
