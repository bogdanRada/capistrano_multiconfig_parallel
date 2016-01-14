module CapistranoMulticonfigParallel
  # helper methods used for capistrano actions
  module CapistranoHelper
    module_function

    def filtered_env_keys_format(keys, version = capistrano_version_2?)
      keys.map { |key| env_key_format(key, version) }
    end

    def env_prefix(key, version = capistrano_version_2?)
      key != CapistranoMulticonfigParallel::ENV_KEY_JOB_ID && version == true ? '-S' : ''
    end

    def env_key_format(key, version = capistrano_version_2?)
      version == true ? key.downcase : key
    end

    def trace_flag(version  = capistrano_version_2?)
      version == true ? '--verbose' : '--trace'
    end

    def setup_flags_for_job(options)
      array_options = []
      options.each do |key, value|
        array_options << "--#{key}=#{value}"
      end
      array_options
    end
  end
end
