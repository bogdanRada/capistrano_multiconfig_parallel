module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module CoreHelper
    extend ActiveSupport::Concern
    included do
      def config_file
        File.join(detect_root.to_s, 'config', 'multi_cap.yml')
      end

      def internal_config_directory
        File.join(root.to_s, 'capistrano_multiconfig_parallel', 'configuration')
      end

      def find_env_multi_cap_root
        ENV['MULTI_CAP_ROOT']
      end

      def detect_root
        if find_env_multi_cap_root
          Pathname.new(find_env_multi_cap_root)
        elsif defined?(::Rails)
          ::Rails.root
        else
          try_detect_capfile
        end
      end

      def log_directory
        File.join(detect_root.to_s, 'log')
      end

      def main_log_file
        File.join(log_directory, 'multi_cap.log')
      end

      def root
        File.expand_path(File.dirname(File.dirname(__dir__)))
      end

      def try_detect_capfile
        root = Pathname.new(FileUtils.pwd)
        root = root.parent unless root.directory?
        root = root.parent until root.children.find { |f| f.file? && f.basename.to_s.downcase == 'capfile' }.present? || root.root?
        fail "Can't detect Capfile in the  application root".red if root.root?
        root
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
      end
    end
  end
end
