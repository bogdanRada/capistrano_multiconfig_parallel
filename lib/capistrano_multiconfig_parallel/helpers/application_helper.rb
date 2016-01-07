require_relative './core_helper'
require_relative './internal_helper'
require_relative './stages_helper'
require_relative './gem_helper'
require_relative './parse_helper'
module CapistranoMulticonfigParallel
  # class that holds the options that are configurable for this gem
  module ApplicationHelper
    include CapistranoMulticonfigParallel::InternalHelper
    include CapistranoMulticonfigParallel::CoreHelper
    include CapistranoMulticonfigParallel::ParseHelper
    include CapistranoMulticonfigParallel::StagesHelper
    include CapistranoMulticonfigParallel::GemHelper
    include CapistranoMulticonfigParallel::CapistranoHelper

    delegate :logger,
             :configuration,
             :configuration_valid?,
             :capistrano_version_2?,
             :capistrano_version,
             :original_args,
             to: :CapistranoMulticonfigParallel

  module_function

    def msg_for_stdin?(message)
      message['action'] == 'stdin'
    end

    def msg_for_task?(message)
      message['task'].present?
    end

    def get_question_details(data)
      /(.*)\?*\s*\:*\s*(\([^)]*\))*/m =~ data
      [regex_last_match(1), regex_last_match(2)]
    end

    def setup_command_line_standard(*args)
      options = args.extract_options!
      args.select(&:present?)
      [args, options]
    end

    def wrap_string(string, options = {})
      options.stringify_keys!
      string.scan(/.{#{options.fetch('length', 80)}}|.+/).map(&:strip).join(options.fetch('character', $INPUT_RECORD_SEPARATOR))
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
