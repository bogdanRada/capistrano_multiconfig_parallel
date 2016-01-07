module CapistranoMulticonfigParallel
  # module used for parsing numbers, strings , arrays and hashes
  module ParseHelper
  module_function

    def check_numeric(num)
      /^[0-9]+/.match(num.to_s)
    end

    def verify_empty_options(options)
      if options.is_a?(Hash)
        options.reject { |_key, value| value.blank? }
      elsif options.is_a?(Array)
        options.reject(&:blank?)
      else
        options
      end
    end

    def verify_array_of_strings(value)
      value = verify_empty_options(value)
      value.find { |row| !row.is_a?(String) }.present? ? warn_array_without_strings(value) : true
    end

    def warn_array_without_strings(value)
      raise ArgumentError, "the array #{value} must contain only task names"
    end

    def check_hash_set(hash, props)
      !Set.new(props).subset?(hash.keys.to_set) || hash.values.find(&:blank?).present?
    end

    def value_is_array?(value)
      value.present? && value.is_a?(Array)
    end

    def strip_characters_from_string(value)
      return '' if value.blank?
      value = value.delete("\r\n").delete("\n")
      value = value.gsub(/\s+/, ' ').strip
      value
    end
  end
end
