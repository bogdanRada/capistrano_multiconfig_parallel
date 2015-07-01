require_relative './initializers/conf'
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

      def default_config
        @default_config ||= Configliere::Param.new
        @default_config.read File.join(CapistranoMulticonfigParallel.root.to_s, 'capistrano_multiconfig_parallel', 'initializers', 'default.yml')
        @default_config.resolve!
      end

      def config_file
        File.join(CapistranoMulticonfigParallel.detect_root.to_s, 'config', 'multi_cap.yml')
      end

      def command_line_params
        [
          {
            name: 'multi_debug',
            type: :boolean,
            description: 'if option is present and has value TRUE , will enable debugging of workers',
            default: default_config[:multi_debug]
          },
          {
            name: 'multi_progress',
            type: :boolean,
            description: "if option is present and has value TRUE  will first execute before any process
                                \t same task but with option '--dry-run'  in order to show progress of how many tasks
                                \t are in total for that task and what is the progress of executing
                                \t This will slow down the workers , because they will execute twice the same task.",
            default: default_config[:multi_progress]
          },
          {
            name: 'multi_secvential',
            type: :boolean,
            description: "If parallel executing does not work for you, you can use this option so that
                                \t each process is executed normally and ouputted to the screen.
                                \t However this means that all other tasks will have to wait for each other to finish before starting ",
            default: default_config[:multi_secvential]
          },
          {
            name: 'websocket_server.enable_debug',
            type: :boolean,
            description: "if option is present and has value TRUE
                                \t will enable debugging of websocket communication between the workers",
            default: default_config[:websocket_server][:enable_debug]
          },
          {
            name: 'development_stages',
            type: Array,
            description: "if option is present and has value an ARRAY of STRINGS,
                                \t each of them will be used as a development stage",
            default: default_config[:development_stages]
          },
          {
            name: 'task_confirmations',
            type: Array,
            description: "if option is present and has value TRUE, will enable user confirmation dialogs
                                 \t before executing each task from option  **--task_confirmations**",
            default: default_config[:task_confirmations]
          },
          {
            name: 'task_confirmation_active',
            type: :boolean,
            description: "if option is present and has value an ARRAY of Strings, and --task_confirmation_active is TRUE ,
                                \t then will require a confirmation from user before executing the task.
                                \t This will syncronize all workers to wait before executing that task, then a confirmation will be displayed,
                                \t and when user will confirm , all workers will resume their operation",
            default: default_config[:task_confirmation_active]
          },
          {
            name: 'syncronize_confirmation',
            type: :boolean,
            description: "if option is present and has value TRUE, all workers will be synchronized to wait for same task
                                \t from the ***task_confirmations** Array before they execute it ",
            default: default_config[:syncronize_confirmation]
          },
          {
            name: 'track_dependencies',
            type: :boolean,
            description: "This should be useed only for Caphub-like applications ,
                                \t in order to deploy dependencies of an application in parallel.
                                \t This is used only in combination with option **--application_dependencies** which is described
                                \t at section **[2.) Multiple applications](#multiple_apps)**",
            default: default_config[:track_dependencies]
          },
          {
            name: 'application_dependencies',
            type: Array,
            description: "This is an array of hashes. Each hash has only the keys
                                \t 'app' ( app name), 'priority' and 'dependencies'
                                \t ( an array of app names that this app is dependent to) ",
            default: default_config[:application_dependencies]
          }
        ]
      end

      def capistrano_options
        command_line_params.map do |param|
          [
            "--#{param[:name]}[=CAP_VALUE]",
            "--#{param[:name]}",
            "[MULTI_CAP] #{param[:description]}",
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

      def check_boolean(c, prop)
        #   return unless c[prop].present?
        raise ArgumentError, "the property `#{prop}` must be boolean" unless [true, false, 'true', 'false'].include?(c[prop].to_s.downcase)
      end

      def configuration_valid?
        configuration
      end

      def check_configuration(c)
        %w(multi_debug multi_progress multi_secvential task_confirmation_active track_dependencies websocket_server.enable_debug).each do |prop|
          c.send("#{prop}=", c[prop.to_sym]) if check_boolean(c, prop.to_sym)
        end
        %w(task_confirmations development_stages).each do |prop|
          c.send("#{prop}=", c[prop.to_sym]) if verify_array_of_strings(c, prop.to_sym)
        end
        c.application_dependencies = c[:application_dependencies] if c[:track_dependencies].to_s.downcase == 'true' && verify_application_dependencies(c[:application_dependencies])
        check_additional_config(c)
      end

      def check_additional_config(c)
        CapistranoMulticonfigParallel::CelluloidManager.debug_enabled = true if c[:multi_debug].to_s.downcase == 'true'
        CapistranoMulticonfigParallel.show_task_progress = true if c[:multi_progress].to_s.downcase == 'true'
        CapistranoMulticonfigParallel.execute_in_sequence = true if c[:multi_secvential].to_s.downcase == 'true'
      end
    end
end
end
