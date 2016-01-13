module CapistranoMulticonfigParallel
  # helper methods used for capistrano actions
  module CapistranoHelper
  module_function

    def filtered_env_keys_format(keys)
      keys.map { |key| env_key_format(key) }
    end

    def env_prefix(key)
      key != CapistranoMulticonfigParallel::ENV_KEY_JOB_ID && capistrano_version_2? ? '-S' : ''
    end

    def env_key_format(key)
      capistrano_version_2? ? key.downcase : key
    end

    def trace_flag
      capistrano_version_2? ? '--verbose' : '--trace'
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
