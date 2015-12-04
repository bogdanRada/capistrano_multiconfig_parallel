require_relative './core_helper'
require_relative './stages_helper'
module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module ApplicationHelper
    include CapistranoMulticonfigParallel::CoreHelper
    include CapistranoMulticonfigParallel::StagesHelper

  module_function

    def strip_characters_from_string(value)
      return unless value.present?
      value = value.delete("\r\n").delete("\n")
      value = value.gsub(/\s+/, ' ').strip if value.present?
      value
    end

    def parse_task_string(string) # :nodoc:
      /^([^\[]+)(?:\[(.*)\])$/ =~ string.to_s

      name           = Regexp.last_match(1)
      remaining_args = Regexp.last_match(2)

      return string, [] unless name
      return name,   [] if     remaining_args.empty?

      args = []

      loop do
        /((?:[^\\,]|\\.)*?)\s*(?:,\s*(.*))?$/ =~ remaining_args

        remaining_args = Regexp.last_match(2)
        args << Regexp.last_match(1).gsub(/\\(.)/, '\1')
        break if remaining_args.blank?
      end

      [name, args]
    end
  end
end
