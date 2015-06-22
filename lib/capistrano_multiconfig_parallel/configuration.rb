require_relative './initializers/conf'
module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module Configuration
    extend ActiveSupport::Concern

    included do
      include Configurations

      configurable Hash, :websocket_server
      configurable Array, :development_stages

      configurable :track_dependencies do |value|
        check_boolean(:track_dependencies, value)
      end

      configurable Array, :application_dependencies do |value|
        value.reject { |val| val.blank? || !val.is_a?(Hash) }
        wrong = value.find do|hash|
          !Set[:app, :priority, :dependencies].subset?(hash.keys.to_set) ||
          hash[:app].blank? ||
          hash[:priority].blank?
          !hash[:priority].is_a?(Numeric) ||
          !hash[:dependencies].is_a?(Array)
        end
        raise ArgumentError, "invalid configuration for #{wrong.inspect}" if wrong.present?
      end

      configurable :task_confirmation_active do |value|
        check_boolean(:task_confirmation_active, value)
      end

      configurable Array, :task_confirmations do |value|
        value.reject(&:blank?)
        if value.find { |row| !row.is_a?(String) }
          raise ArgumentError, 'the array must contain only task names'
        end
      end

      configuration_defaults do |c|
        c.task_confirmations = ['deploy:symlink:release']
        c.task_confirmation_active = false
        c.track_dependencies = false
        c.websocket_server = { enable_debug: false }
        c.development_stages = ['development', 'webdev']
      end

      not_configured do |prop| # omit the arguments to get a catch-all not_configured
        raise NoMethodError, "Please configure the property `#{prop}` by assigning a value of type #{configuration.property_type(prop)}"
      end

      def self.value_is_boolean?(value)
        [true, false, 'true', 'false'].include?(value)
      end

      def self.check_boolean(prop, value)
        unless value_is_boolean?(value)
          raise ArgumentError, "the property `#{prop}` must be boolean"
        end
      end

      def self.configuration_valid?
        configuration.nil? &&
          configuration.task_confirmations &&
          ((configuration.track_dependencies && configuration.application_dependencies) ||
            configuration.track_dependencies == false)
      end
    end
  end
end
