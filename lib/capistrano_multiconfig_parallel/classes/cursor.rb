require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to fetch cursor position before displaying terminal table
  class Cursor
    class << self
      include CapistranoMulticonfigParallel::ApplicationHelper

      def fetch_terminal_size
        size = (dynamic_size_stty || dynamic_size_tput || `echo $LINES $COLUMNS`)
        size = strip_characters_from_string(size).split(' ')
        { rows: size[0].to_i, columns: size[1].to_i }
      end

      def fetch_position
        res = ''
        $stdin.raw do |stdin|
          $stdout << "\e[6n"
          $stdout.flush
          while (line = stdin.getc) != 'R'
            res << line if line
          end
        end
        position = res.match(/(?<row>\d+);(?<column>\d+)/)
        { row: position[:row].to_i, column: position[:column].to_i }
      end


      def display_on_screen(string, options = {})
        options = options.is_a?(Hash) ? options.stringify_keys : {}
        position = options.fetch('position', nil)
        clear_scren =  options.fetch('clear_screen', false)
        handle_string_display(position, clear_scren, string)
      end

      def move_to_home!(row = 2, column = 1)
        position_cursor(row, column)
        erase_from_current_line_to_bottom
      end

      private

      def dynamic_size_stty
       size = %x{stty size 2>/dev/null}
       size.present? ? size : nil
      end

      def dynamic_size_tput
        lines %x{tput lines 2>/dev/null}
        cols = %x{tput cols 2>/dev/null}
        lines.present? && cols.present? ? "#{lines} #{cols}" : nil
      end

      def handle_string_display(position, clear_scren, string)
        if clear_scren.to_s == 'true'
          terminal_clear_display(string)
        elsif position.present?
          display_string_at_position(position, string)
        end
      end

      def terminal_clear_display(string)
        terminal_clear
        puts string
      end

      def display_string_at_position(position, string)
        go_to_position(position)
        erase_from_current_line_to_bottom
        go_to_position(position)
        puts string
      end

      def erase_from_current_line_to_bottom
        puts "\e[J"
      end

      def go_to_position(position)
        position_cursor(position[:row], position[:column])
      end

      def position_cursor(line, column)
        puts("\e[#{line};#{column}H")
      end

      def terminal_clear
        system('cls') || system('clear') || puts("\e[H\e[2J")
      end

    end
  end
end
