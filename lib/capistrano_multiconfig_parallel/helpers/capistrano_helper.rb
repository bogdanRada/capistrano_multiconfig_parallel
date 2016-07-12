module CapistranoMulticonfigParallel
  # helper methods used for capistrano actions
  module CapistranoHelper
  module_function

    def filtered_env_keys_format(keys, version = false)
      keys.map { |key| env_key_format(key, version) }
    end

    def env_prefix(key, version = false)
      key != CapistranoMulticonfigParallel.env_job_key_id && version == true ? '-S' : ''
    end

    def env_key_format(key, version = false)
      version == true ? key.downcase : key
    end

    def trace_flag(version = false)
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
