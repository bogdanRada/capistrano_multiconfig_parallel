module CapistranoMulticonfigParallel
  # methods used for the interactive menu where are listed all aplications
  class InteractiveMenu
    def show_all_websites_interactive_menu(applications)
      msg = ''
      choices = []
      print_menu_choices(msg, choices, applications)
      print "\nYou selected"
      msg = ' nothing'
      result = ''
      applications.each_with_index do |option_name, index|
        next unless choices[index].present?
        print(" #{option_name}")
        msg = ''
        result += "#{option_name},"
      end
      print "#{msg}\n"
      result
    end

    def confirm_option_selected
      print 'Enter a comma-separated list of option numbers or one single option number (again to uncheck, ENTER when done): '
      $stdin.gets.squeeze(' ').strip
    end

    def print_menu_choices(msg, choices, applications)
      while print_all_websites_available_options(applications, msg, choices) && (option = confirm_option_selected).present?
        if /^[0-9,]+/.match(option)
          handle_menu_option(msg, option, choices, applications)
        else
          msg = "Invalid option: #{option}\n  "
          next
        end
      end
    end

    def print_all_websites_available_options(applications, msg, choices)
      puts 'Available options:'
      applications.each_with_index do |option, index|
        puts "#{(index + 1)} #{choices[index].present? ? "#{choices[index]}" : ''}) #{option} "
      end
      puts "\n#{msg}" if msg.present?
      true
    end

    def handle_menu_option(msg, option, choices, applications)
      arr_in = option.split(',')
      arr_in.each_with_index do |number_option, _index|
        num = number_option.to_i
        if /^[0-9]+/.match(num.to_s) && ((num.to_i > 0 && num.to_i <= applications.size))
          num -= 1
          msg += "#{applications[num]} was #{choices[num].present? ? 'un' : '' }checked\n"
          choices[num] = choices[num].blank? ? '+' : ' '
        else
          msg = "Invalid option: #{num}\n"
          next
        end
      end
    end
  end
end
