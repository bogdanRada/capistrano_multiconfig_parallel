require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to start the web server for websockets
  class WebServer < CelluloidPubsub::WebServer
    include CapistranoMulticonfigParallel::ApplicationHelper
    def initialize(*args)
      super(*args)
    rescue => exc
      rescue_error(exc, 'stderr')
      # fails silently
    end
  end
end
