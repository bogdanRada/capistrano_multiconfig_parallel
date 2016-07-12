module CapistranoMulticonfigParallel
  # internal helpers for logging mostly
  module InternalHelper
    module_function

    def get_current_gem_name
      searcher = if Gem::Specification.respond_to? :find
        # ruby 2.0
        Gem::Specification
      elsif Gem.respond_to? :searcher
        # ruby 1.8/1.9
        Gem.searcher.init_gemspecs
      end
      spec = unless searcher.nil?
        searcher.find do |spec|
          File.fnmatch(File.join(spec.full_gem_path,'*'), __FILE__)
        end
      end
      spec.name if spec.present?
    end

  def get_current_gem_name
      searcher = if Gem::Specification.respond_to? :find
        # ruby 2.0
        Gem::Specification
      elsif Gem.respond_to? :searcher
        # ruby 1.8/1.9
        Gem.searcher.init_gemspecs
      end
      spec = unless searcher.nil?
        searcher.find do |spec|
          File.fnmatch(File.join(spec.full_gem_path,'*'), __FILE__)
        end
      end
      spec.name if spec.present?
    end

    def multi_level_prop(config, prop)
      prop.split('.').each { |new_prop| config = config[new_prop] }
      config
    end

    def internal_config_directory
     File.join(root.to_s, get_current_gem_name, 'configuration')
    end

    def internal_config_file
      File.join(internal_config_directory, 'default.yml')
    end

    def default_internal_config
      @default_config ||= fetch_default_internal_config
      @default_config
    end

    def fetch_default_internal_config
      config = YAML.load_file(internal_config_file)['default_config']
      new_config = config.map do |hash|
        setup_default_configuration_types(hash)
      end
      default_internal_configuration_params(new_config)
    end

    def default_config_keys
      default_internal_config.map { |array| array[0].to_s }.concat([CapistranoMulticonfigParallel.env_job_key_id, 'capistrano_version'])
    end

    def arg_is_in_default_config?(arg)
      default_config_keys.find { |key| key == arg.split('=')[0].tr('--', '') }.present?
    end

    def default_internal_configuration_params(new_config)
      array = []
      new_config.each do |hash|
        array << [hash['name'], sliced_default_config(hash)]
      end
      array
    end

    def sliced_default_config(hash)
      hash.slice('type', 'description', 'default', 'required')
    end

    def setup_default_configuration_types(hash)
      hash.each_with_object({}) do |(key, value), memo|
        memo[key] = (key == 'type') ? find_config_type(value) : value
        memo
      end
    end

    def find_config_type(type)
      type = type.to_s
      %w(boolean filename string).include?(type) ? type.delete(':').to_sym : type.constantize
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
      fail "Can't detect Capfile in the  application root".red if root.blank?
    end

    def pwd_parent_dir
      pwd_directory.directory? ? pwd_directory : pwd_directory.parent
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

    def try_detect_file(filename = 'capfile')
      root = pwd_parent_dir
      root = root.parent until find_file_in_directory(root, filename)
      pathname_is_root?(root) ? nil : root
    end

    def detect_root
      if find_env_multi_cap_root
        Pathname.new(find_env_multi_cap_root)
      elsif defined?(::Rails)
        ::Rails.root
      else
        root = try_detect_file
        fail_capfile_not_found(root)
        root
      end
    end

    def log_directory
      log_dir = configuration.log_dir || detect_root.to_s
      File.join(log_dir.to_s, 'log')
    end

    def main_log_file
      File.join(log_directory, 'multi_cap.log')
    end

    def custom_commands
      ['deploy_multi_stages']
    end

    def create_log_file(file_path)
      return if file_path.blank?
      directory = File.dirname(file_path)
      FileUtils.mkdir_p(directory) unless File.directory?(directory)
      FileUtils.touch(file_path) unless File.file?(file_path)
    end

    def enable_main_log_file
      create_log_file(main_log_file)
      log_file = File.open(main_log_file, 'w')
      log_file.sync = true
    end
  end
end
