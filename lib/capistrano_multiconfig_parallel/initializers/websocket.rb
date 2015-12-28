require 'celluloid/websocket/client/connection'
# DIRTY HACK TO make websocket-driver to not use Capistrano::DSL env
Celluloid::WebSocket::Client::Connection.class_eval do
  def env
    env_hash = ENV.each_with_object({}) do |(key, value), memo|
      memo['HTTP_' + key.upcase.tr('-', '_')] = value
      memo
    end
    env_hash.reverse_merge!('REQUEST_METHOD'                => 'GET',
                            'HTTP_CONNECTION'               => 'Upgrade',
                            'HTTP_UPGRADE'                  => 'websocket',
                            'HTTP_ORIGIN'                  => @url,
                            'HTTP_SEC_WEBSOCKET_KEY'        => SecureRandom.uuid,
                            'HTTP_SEC_WEBSOCKET_PROTOCAL'    => 'ws',
                            'HTTP_SEC_WEBSOCKET_VERSION'    => SecureRandom.random_number(15))
    ::Rack::MockRequest.env_for(@url, env_hash)
  end
end
