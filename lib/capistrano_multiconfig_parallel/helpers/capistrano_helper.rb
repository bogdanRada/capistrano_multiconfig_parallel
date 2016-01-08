module CapistranoMulticonfigParallel
  # helper methods used for capistrano actions
  module CapistranoHelper
  module_function

    def filtered_env_keys_format(keys)
      capistrano_version_2? ? keys.map(&:downcase) : keys
    end

    def env_prefix
      capistrano_version_2? ? '-S' : ''
    end

    def env_key_format(key)
      capistrano_version_2? ? key.downcase : key
    end

    def trace_flag
      capistrano_version_2? ? '--verbose' : '--trace'
    end
  end
end
