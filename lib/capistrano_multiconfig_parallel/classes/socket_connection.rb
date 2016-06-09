require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  class SocketConnection
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_reader :client, :server, :options, :read_sockets, :write_sockets

    def initialize(actor, options = {})
      @options = options.with_indifferent_access if options.is_a?(Hash)
      @current_actor = actor
      @client = tcp_socket_enabled? ? pubsub_tcp_client : nil
      start_server if subscription_channel.present? && !tcp_socket_enabled?
    end

    def tcp_socket_enabled?
      @options[:tcp_socket_enabled].present?
    end

    def subscription_channel
      @options.fetch(:subscription_channel, nil) || nil
    end

    def debug_websocket
      @options.fetch(:debug_websocket, false) || false
    end

    def publish_to_channel(channel, data, client_options = {})
      if tcp_socket_enabled?
        @client ||= pubsub_tcp_client(client_options[:subscription_channel])
        @client.publish(channel, data)
      else
        @client ||= ::UNIXSocket.new(channel)
        log_to_file("worker #{@job_id} tries to send to SOCKET #{@rake_socket_file} message #{data.inspect} with encoded #{encode_job(data)}")
        @client.puts(encode_job(data))
      end
    end

    def subscribe_to_channel(channel)
      if tcp_socket_enabled?
        @client ||= pubsub_tcp_client
        @client.subscribe(channel)
      else
        start_server(channel)
      end
    end

    def default_tcp_settins(channel = nil)
      {
        actor: current_actor,
        enable_debug: debug_websocket,
        log_file_path: options.fetch(:log_file_path, nil),
        channel: channel.present? ? channel : subscription_channel
      }
    end

    def pubsub_tcp_client(channel = nil)
      @client = CelluloidPubsub::Client.new(default_tcp_settins(channel))
    end

    def on_message(message)
      message = message.with_indifferent_access if message.is_a?(Hash)
      @current_actor.on_message(message)
    end

    def start_server(channel = nil)
      return if tcp_socket_enabled?
      subscription_channel = "/tmp/#{default_tcp_settins(channel)[:channel]}.sock"
      FileUtils.rm(subscription_channel) if File.exists?(subscription_channel)
      @server         = ::UNIXServer.new(subscription_channel)

      @read_sockets   = [@server]
      @write_sockets  = []
      handle_sockets
    end


    def handle_sockets
      Thread.new do
        loop do
          readables, writeables, _ = ::IO.select(@read_sockets, @write_sockets)
          handle_readables(readables)
        end
      end
    end

    def handle_readables(sockets)
      sockets.each do |socket|
        if socket == @server
          conn = socket.accept
          @read_sockets << conn
          @write_sockets << conn
        else
          while message = socket.gets
            log_to_file("worker #{@job_id} tries to decode SOCKET #{message.inspect}")
            ary = decode_job(message.chomp)
            log_to_file("worker #{@job_id} has decoded message from SOCKET #{ary.inspect}")
            on_message(ary)
          end
        end
      end
    end

    def encode_job(job)
      # remove silly newlines injected by Ruby's base64 library
      Base64.encode64(Marshal.dump(job)).delete("\n")
    end

    def decode_job(job)
      Marshal.load(Base64.decode64(job))
    end

  end
end
