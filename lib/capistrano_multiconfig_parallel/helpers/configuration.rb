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
    end
  end
end
