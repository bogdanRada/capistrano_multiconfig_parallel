require_relative './application_helper'
module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module Configuration
    extend ActiveSupport::Concern
    include CapistranoMulticonfigParallel::ApplicationHelper

    included do
      attr_reader :configuration

      def configuration
        @config ||= fetch_configuration
        @config
      end

      def fetch_configuration
        @fetched_config = Configliere::Param.new
        setup_default_config
        setup_configuration
      end

      def setup_default_config
        default_internal_config.each do |array_param|
          @fetched_config.define array_param[0], array_param[1].symbolize_keys
        end
      end

      def setup_configuration
        @fetched_config.read config_file if File.file?(config_file)
        @fetched_config.use :commandline

        @fetched_config.use :config_block
        validate_configuration
      end

      def validate_configuration
        @fetched_config.finally do |config|
          @check_config = config.stringify_keys
          check_configuration
        end
        @fetched_config.process_argv!
        @fetched_config.resolve!
      end

      def verify_application_dependencies(value, props)
        return unless value.is_a?(Array)
        value.reject { |val| val.blank? || !val.is_a?(Hash) }
        wrong = check_array_of_hash(value, props.map(&:to_sym))
        raise ArgumentError, "invalid configuration for #{wrong.inspect}" if wrong.present?
      end

      def check_array_of_hash(value, props)
        value.find do|hash|
          check_hash_set(hash, props)
        end
      end

      def check_boolean(prop)
        raise ArgumentError, "the property `#{prop}` must be boolean" unless %w(true false).include?(@check_config[prop].to_s.downcase)
      end

      def configuration_valid?
        configuration
      end

      def check_boolean_props(props)
        props.each do |prop|
          @check_config.send("#{prop}=", @check_config[prop]) if check_boolean(prop)
        end
      end

      def check_array_props(props)
        props.each do |prop|
          value =  @check_config[prop]
          @check_config.send("#{prop}=", value) if value_is_array?(value) && verify_array_of_strings(value)
        end
      end

      def check_configuration
        check_boolean_props(%w(multi_debug multi_secvential websocket_server.enable_debug))
        check_array_props(%w(task_confirmations development_stages apply_stage_confirmation))
        verify_application_dependencies(@check_config['application_dependencies'], %w(app priority dependencies))
      end
    end
  end
end
