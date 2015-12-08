require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # methods used for the interactive menu where are listed all aplications
  class InteractiveMenu
    include CapistranoMulticonfigParallel::ApplicationHelper

    attr_accessor :msg, :choices, :applications

    def initialize(applications)
      @applications = applications
      @msg = ' '
      @choices = {}
    end

    def fetch_menu
      print_menu_choices
      default_printing
      result = show_all_websites_interactive_menu
      print "#{@msg}\n"
      strip_characters_from_string(result).split(',')
    end

  private

    def default_printing
      print "\nYou selected"
      @msg = ' nothing'
    end

    def show_all_websites_interactive_menu
      result = ''
      @applications.each_with_index do |option_name, index|
        result += "#{option_name}," if choices[index].present?
        print_option_name(option_name, index)
      end
      result
    end

    def print_option_name(option_name, index)
      return unless @choices[index].present?
      print(" #{option_name}")
      @msg = ''
    end

    def confirm_option_selected
      print 'Enter a comma-separated list of option numbers or one single option number (again to uncheck, ENTER when done): '
      $stdin.gets.squeeze(' ').strip
    end

    def print_menu_choices
      while print_all_websites_available_options && (option = confirm_option_selected).present?
        if /^[0-9,]+/.match(option)
          handle_menu_option(option)
        else
          @msg = "Invalid option: #{option}\n  "
          next
        end
      end
    end

    def print_all_websites_available_options
      puts 'Available options:'
      @applications.each_with_index do |option, index|
        print_selected_index_option(index, option)
      end
      puts "\n#{@msg}" if @msg.present?
      true
    end

    def handle_menu_option(option)
      option.split(',').each_with_index do |number_option, _index|
        num = number_option.to_i
        show_option_selected(num)
        setup_message_invalid(num)
        next
      end
    end

    def check_number_selected(num)
      check_numeric(num) && (num > 0 && num <= @applications.size)
    end

    def show_option_selected(num)
      return unless check_number_selected(num)
      num -= 1
      @msg += "#{@applications[num]} was #{@choices[num].present? ? 'un' : ''}checked\n"
      setup_choices_number(num)
    end

    def setup_message_invalid(num)
      return if check_number_selected(num)
      @msg = "Invalid option: #{num}\n"
    end

    def print_selected_index_option(index, option)
      puts "#{(index + 1)} #{fetch_choice(index)}) #{option} "
    end

    def setup_choices_number(num)
      @choices[num] = @choices[num].blank? ? '+' : ' '
    end

    def fetch_choice(num)
      @choices.fetch(num, '')
    end
  end
end
