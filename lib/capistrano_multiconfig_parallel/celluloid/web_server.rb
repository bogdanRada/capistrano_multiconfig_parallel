require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to start the web server for websockets
  class WebServer < CelluloidPubsub::WebServer
    include CapistranoMulticonfigParallel::ApplicationHelper
    def initialize(*args)
      super(*args)
    rescue => exc
      log_error(exc)
      # fails silently
    end
  end
end
