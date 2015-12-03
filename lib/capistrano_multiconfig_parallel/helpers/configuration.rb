module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module Configuration
    extend ActiveSupport::Concern

    included do
      attr_reader :configuration

      def configuration
        @config ||= fetch_configuration
        @config
      end

      def fetch_configuration
        @fetched_config = Configliere::Param.new
        command_line_params.each do |param|
          param_type = change_config_type(param['type'].to_s)
          @fetched_config.define param['name'], type: param_type, description: param['description'], default: param['default']
        end

        ARGV.clear

        CapistranoMulticonfigParallel.original_args.each { |a| ARGV << a }
        @fetched_config.read config_file if File.file?(config_file)
        @fetched_config.use :commandline

        @fetched_config.use :config_block
        @fetched_config.finally do |c|
          check_configuration(c)
        end
        @fetched_config.process_argv!
        @fetched_config.resolve!
      end

      def command_line_params
        @default_config ||= YAML.load_file(File.join(internal_config_directory, 'default.yml'))['default_config']
        @default_config
      end

      def verify_array_of_strings(value)
        return true if value.blank?
        value.reject(&:blank?)
        raise ArgumentError, 'the array must contain only task names' if value.find { |row| !row.is_a?(String) }
      end

      def verify_application_dependencies(c, prop, props)
        value = c[prop.to_sym]
        return unless value.is_a?(Array)
        value.reject { |val| val.blank? || !val.is_a?(Hash) }
        wrong = check_array_of_hash(value, props.map(&:to_sym))
        raise ArgumentError, "invalid configuration for #{wrong.inspect}" if wrong.present?
      end

      def check_array_of_hash(value, props)
        value.find do|hash|
          !Set.new(props).subset?(hash.keys.to_set) ||
            hash.values.find(&:blank?).present?
        end
      end

      def check_boolean(c, prop)
        raise ArgumentError, "the property `#{prop}` must be boolean" unless %w(true false).include?(c[prop].to_s.downcase)
      end

      def configuration_valid?
        configuration
      end

      def check_boolean_props(c, props)
        props.each do |prop|
          c.send("#{prop}=", c[prop.to_sym]) if check_boolean(c, prop.to_sym)
        end
      end

      def check_array_props(c, props)
        props.each do |prop|
          c.send("#{prop}=", c[prop.to_sym]) if c[prop.to_sym].is_a?(Array) && verify_array_of_strings(c[prop.to_sym])
        end
      end

      def check_configuration(c)
        check_boolean_props(c, %w(multi_debug multi_secvential websocket_server.enable_debug))
        check_array_props(c, %w(task_confirmations development_stages apply_stage_confirmation))
        verify_application_dependencies(c, 'application_dependencies', %w(app priority dependencies))
        CapistranoMulticonfigParallel::CelluloidManager.debug_enabled = true if c[:multi_debug].to_s.downcase == 'true'
      end
    end
  end
end
