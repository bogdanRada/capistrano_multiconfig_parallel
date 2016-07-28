require_relative './core_helper'
require_relative './internal_helper'
require_relative './parse_helper'
module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module Configuration
    include CapistranoMulticonfigParallel::CoreHelper
    include CapistranoMulticonfigParallel::InternalHelper
    include CapistranoMulticonfigParallel::ParseHelper

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
      @fetched_config.use :commandline
      @fetched_config.process_argv!
      read_config_file
      @fetched_config.use :config_block
      validate_configuration
    end

    def validate_configuration
      @fetched_config.finally do |config|
        check_configuration(config)
      end
      @fetched_config.resolve!
      @fetched_config
    end

    def read_config_file
      return if CapistranoMulticonfigParallel.original_args.present? && CapistranoMulticonfigParallel.original_args.include?('--help')
      user = Etc.getlogin
      config_file_path = File.join(Dir.home(user), "multi_cap.yml")
      if File.exists?(config_file_path)
        @fetched_config.config_dir  = File.dirname(config_file_path)
      else
        @fetched_config.config_dir = @fetched_config.config_dir.present? ? File.expand_path(@fetched_config.config_dir) : try_detect_file('multi_cap.yml')
        config_file_path = @fetched_config.config_dir.present? ? File.join(@fetched_config.config_dir, 'multi_cap.yml') : nil
      end
      config_file = File.expand_path(config_file_path || File.join(detect_root.to_s, 'config', 'multi_cap.yml'))
      @fetched_config.config_dir = File.dirname(config_file)
      @fetched_config.log_dir = config_file_path.present? ? File.dirname(config_file) : File.dirname(File.dirname(config_file))
      @fetched_config.read config_file if File.file?(config_file)
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
      value = get_prop_config(prop)
      if %w(true false).include?(value.to_s.downcase)
        true
      else
        raise ArgumentError, "the property `#{prop}` must be boolean"
      end
    end

    def configuration_valid?
      configuration
    end

    def check_boolean_props(props)
      props.each do |prop|
        @check_config[prop] = get_prop_config(prop) if check_boolean(prop)
      end
    end

    def check_array_props(props)
      props.each do |prop|
        value = get_prop_config(prop)
        @check_config[prop] = value if value_is_array?(value) && verify_array_of_strings(value)
      end
    end

    def check_string_props(props)
      props.each do |prop|
        value = get_prop_config(prop)
        @check_config[prop] = value if value.is_a?(String)
      end
    end

    def get_prop_config(prop, config = @check_config)
      if prop.include?('.')
        multi_level_prop(config, prop)
      else
        config[prop]
      end
    end

    def check_directories(props)
      props.each do |prop|
        value = get_prop_config(prop)
        @check_config[prop] = value if value.present? && File.directory?(value)
      end
    end

    def check_configuration(config)
      @check_config = config.stringify_keys
      check_boolean_props(%w(multi_debug multi_secvential websocket_server.enable_debug terminal.clear_screen check_app_bundler_dependencies))
      check_string_props(%w(websocket_server.adapter))
      check_array_props(%w(task_confirmations development_stages apply_stage_confirmation))
      check_directories(%w(log_dir config_dir))
      verify_application_dependencies(@check_config['application_dependencies'], %w(app priority dependencies))
    end
  end
end
