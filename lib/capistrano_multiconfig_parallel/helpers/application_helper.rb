require_relative './core_helper'
require_relative './internal_helper'
module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module ApplicationHelper
    include CapistranoMulticonfigParallel::InternalHelper
    include CapistranoMulticonfigParallel::CoreHelper

    delegate :logger,
             :configuration,
             :configuration_valid?,
             :original_args,
             to: :CapistranoMulticonfigParallel

  module_function

    def setup_command_line_standard(*args)
      options = args.extract_options!
      args.select(&:present?)
      [args, options]
    end

    def wrap_string(string, options = {})
      options.stringify_keys!
      string.scan(/.{#{options.fetch('length', 80)}}|.+/).map(&:strip).join(options.fetch('character', $INPUT_RECORD_SEPARATOR))
    end

    def find_loaded_gem(name)
      Gem.loaded_specs.values.find { |repo| repo.name == name }
    end

    def percent_of(index, total)
      index.to_f / total.to_f * 100.0
    end

    def multi_fetch_argv(args)
      options = {}
      args.each do |arg|
        if arg =~ /^(\w+)=(.*)$/m
          options[Regexp.last_match(1)] = Regexp.last_match(2)
        end
      end
      options
    end

    def action_confirmed?(result)
      result.present? && result.downcase == 'y'
    end

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
      value.reject(&:blank?)
      warn_array_without_strings(value)
    end

    def warn_array_without_strings(value)
      raise ArgumentError, 'the array must contain only task names' if value.find { |row| !row.is_a?(String) }
    end

    def check_hash_set(hash, props)
      !Set.new(props).subset?(hash.keys.to_set) || hash.values.find(&:blank?).present?
    end

    def value_is_array?(value)
      value.present? && value.is_a?(Array)
    end

    def strip_characters_from_string(value)
      return unless value.present?
      value = value.delete("\r\n").delete("\n")
      value = value.gsub(/\s+/, ' ').strip
      value
    end

    def regex_last_match(number)
      Regexp.last_match(number)
    end

    def parse_task_string(string) # :nodoc:
      name, remaining_args = fetch_parsed_string(string)
      name.present? ? find_remaining_args(name, remaining_args) : [string, []]
    end

    def fetch_parsed_string(string)
      /^([^\[]+)(?:\[(.*)\])$/ =~ string.to_s
      [regex_last_match(1), regex_last_match(2)]
    end

    def fetch_remaining_arguments(args, remaining_args)
      /((?:[^\\,]|\\.)*?)\s*(?:,\s*(.*))?$/ =~ remaining_args
      args << regex_last_match(1).gsub(/\\(.)/, '\1')
      regex_last_match(2)
    end

    def find_remaining_args(name, remaining_args)
      args = []
      loop do
        remaining_args = fetch_remaining_arguments(args, remaining_args)
        break if remaining_args.blank?
      end
      [name, args]
    end
  end
end
