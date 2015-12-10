require_relative './core_helper'
require_relative './internal_helper'
require_relative './stages_helper'
module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module ApplicationHelper
    include CapistranoMulticonfigParallel::InternalHelper
    include CapistranoMulticonfigParallel::CoreHelper
    include CapistranoMulticonfigParallel::StagesHelper

    delegate :logger,
    :configuration,
    :configuration_valid?,
    :original_args,
    to: :CapistranoMulticonfigParallel

    module_function

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
      /^([^\[]+)(?:\[(.*)\])$/ =~ string.to_s

      name           = regex_last_match(1)
      remaining_args = regex_last_match(2)

      return string, [] unless name
      return name,   [] if     remaining_args.empty?

      args = find_remaining_args(remaining_args)
      [name, args]
    end

    def find_remaining_args(remaining_args)
      args = []
      loop do
        /((?:[^\\,]|\\.)*?)\s*(?:,\s*(.*))?$/ =~ remaining_args

        remaining_args = regex_last_match(2)
        args << regex_last_match(1).gsub(/\\(.)/, '\1')
        break if remaining_args.blank?
      end
      args
    end
  end
end
