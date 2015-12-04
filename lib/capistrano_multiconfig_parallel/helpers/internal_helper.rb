module CapistranoMulticonfigParallel
  # internal helpers for logging mostly
  module InternalHelper
  module_function

    def internal_config_directory
      File.join(root.to_s, 'capistrano_multiconfig_parallel', 'configuration')
    end

    def internal_config_file
      File.join(internal_config_directory, 'default.yml')
    end

    def default_internal_config
      @default_config ||= YAML.load_file(internal_config_file)['default_config']
      @default_config
    end

    def find_env_multi_cap_root
      ENV['MULTI_CAP_ROOT']
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

    def detect_root
      if find_env_multi_cap_root
        Pathname.new(find_env_multi_cap_root)
      elsif defined?(::Rails)
        ::Rails.root
      else
        try_detect_capfile
      end
    end

    def config_file
      File.join(detect_root.to_s, 'config', 'multi_cap.yml')
    end

    def log_directory
      File.join(detect_root.to_s, 'log')
    end

    def main_log_file
      File.join(log_directory, 'multi_cap.log')
    end

    def custom_commands
      ['deploy_multi_stages']
    end

    def enable_main_log_file
      FileUtils.mkdir_p(log_directory) unless File.directory?(log_directory)
      FileUtils.touch(main_log_file) unless File.file?(main_log_file)
      log_file = File.open(main_log_file, 'w')
      log_file.sync = true
    end
  end
end
