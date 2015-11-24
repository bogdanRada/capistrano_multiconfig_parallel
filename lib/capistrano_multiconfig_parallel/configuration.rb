module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module Configuration
    extend ActiveSupport::Concern

    class_methods do
      attr_accessor :configuration

      def configuration
        @config ||= Configliere::Param.new
        @config.use :commandline
        command_line_params.each do |param|
          @config.define param[:name], type: param[:type], description: param[:description], default: param[:default]
        end

        ARGV.clear
        CapistranoMulticonfigParallel.original_args.each { |a| ARGV << a }
        @config.read config_file if File.file?(config_file)
        @config.merge(Settings.use(:commandline).resolve!)

        @config.use :config_block
        @config.finally do |c|
          check_configuration(c)
        end
        @config.resolve!
      end

      def config_file
        File.join(CapistranoMulticonfigParallel.detect_root.to_s, 'config', 'multi_cap.yml')
      end

      def internal_config_directory
        File.join(CapistranoMulticonfigParallel.root.to_s, 'capistrano_multiconfig_parallel', 'initializers')
      end

      def command_line_params
        @default_config ||= Configliere::Param.new
        @default_config.read File.join(internal_config_directory, 'default.yml')
        @default_config.resolve!
        @default_config[:default_config].map do |item|
          item[:type] = change_config_type(item[:type].to_s)
          item
        end
      end

      def change_config_type(type)
        type.include?(':') ? type.delete(':').to_sym : type.constantize
      end

      def capistrano_options
        command_line_params.map do |param|
          [
            "--#{param[:name]}[=CAP_VALUE]",
            "--#{param[:name]}",
            "[MULTI_CAP] #{param[:description]}. By default #{param[:default]}",
            lambda do |_value|
            end
          ]
        end
      end

      def verify_array_of_strings(c, prop)
        value = c[prop]
        return unless value.present?
        value.reject(&:blank?)
        raise ArgumentError, 'the array must contain only task names' if value.find { |row| !row.is_a?(String) }
      end

      def verify_application_dependencies(value)
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

      def verify_app_dependencies(stages)
        applications = stages.map { |stage| stage.split(':').reverse[1] }
        wrong = configuration.application_dependencies.find do |hash|
          !applications.include?(hash[:app]) || (hash[:dependencies].present? && hash[:dependencies].find { |val| !applications.include?(val) })
        end
        raise ArgumentError, "invalid configuration for #{wrong.inspect}" if wrong.present?
      end

      def check_boolean(c, prop)
        #   return unless c[prop].present?
        raise ArgumentError, "the property `#{prop}` must be boolean" unless [true, false, 'true', 'false'].include?(c[prop].to_s.downcase)
      end

      def configuration_valid?(stages)
        configuration
        verify_app_dependencies(stages) if configuration.application_dependencies.present?
      end

      def check_configuration(c)
        %w(multi_debug multi_secvential websocket_server.enable_debug).each do |prop|
          c.send("#{prop}=", c[prop.to_sym]) if check_boolean(c, prop.to_sym)
        end
        %w(task_confirmations development_stages apply_stage_confirmation).each do |prop|
          c.send("#{prop}=", c[prop.to_sym]) if verify_array_of_strings(c, prop.to_sym)
        end
        c.application_dependencies = c[:application_dependencies] if verify_application_dependencies(c[:application_dependencies])
        check_additional_config(c)
      end

      def check_additional_config(c)
        CapistranoMulticonfigParallel::CelluloidManager.debug_enabled = true if c[:multi_debug].to_s.downcase == 'true'
      end
    end
  end
end
