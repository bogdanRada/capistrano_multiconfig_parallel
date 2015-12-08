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

    def pathname_is_root?(root)
      root.root?
    end

    def fail_capfile_not_found(root)
      fail "Can't detect Capfile in the  application root".red if pathname_is_root?(root)
    end

    def pwd_parent_dir
      pwd_directory.parent unless pwd_directory.directory?
    end

    def pwd_directory
      Pathname.new(FileUtils.pwd)
    end

    def check_file(file, filename)
      file.file? && file.basename.to_s.downcase == filename.to_s.downcase
    end

    def find_file_in_directory(root, filename)
      root.children.find { |file| check_file(file, filename) }.present? || pathname_is_root?(root)
    end

    def try_detect_capfile
      root = pwd_parent_dir
      root = root.parent until find_file_in_directory(root, 'capfile')
      fail_capfile_not_found(root)
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
