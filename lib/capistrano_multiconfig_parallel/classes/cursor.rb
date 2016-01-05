require_relative '../helpers/application_helper'
module CapistranoMulticonfigParallel
  # class used to fetch cursor position before displaying terminal table
  # http://ispltd.org/mini_howto:ansi_terminal_codes
  class Cursor
    class << self
      include CapistranoMulticonfigParallel::ApplicationHelper

      def display_on_screen(string, options = {})
        options = options.is_a?(Hash) ? options.stringify_keys : {}
        handle_string_display(string, options)
      end

    private

      def move_to_home!(row = 0, column = 1)
        erase_screen
        position_cursor(row, column)
      end

      def fetch_terminal_size
        size = (dynamic_size_stty || dynamic_size_tput || `echo $LINES $COLUMNS`)
        size = strip_characters_from_string(size).split(' ')
        { rows: size[0].to_i, columns: size[1].to_i }
      end

      def fetch_cursor_position(table_size, position, previously_erased_screen)
        final_position = position || fetch_position
        terminal_rows = fetch_terminal_size
        screen_erased = refetch_position?(table_size, terminal_rows, final_position)
        if screen_erased == true
          move_to_home! if previously_erased_screen != true
          final_position = fetch_position
          terminal_rows = fetch_terminal_size
        end
        [final_position, terminal_rows, screen_erased]
      end

      def refetch_position?(table_size, terminal_size, position)
        terminal_rows = terminal_size[:rows]
        row_position = position[:row]
        terminal_rows.zero? || (terminal_rows.nonzero? && row_position >= (terminal_rows / 2)) || (table_size >= (terminal_rows - row_position))
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

      def dynamic_size_stty
        size = `stty size 2>/dev/null`
        size.present? ? size : nil
      end

      def dynamic_size_tput
        lines `tput lines 2>/dev/null`
        cols = `tput cols 2>/dev/null`
        lines.present? && cols.present? ? "#{lines} #{cols}" : nil
      end

      def handle_string_display(string, options)
        position = options.fetch('position', nil)
        table_size = options.fetch('table_size', 0)
        if options.fetch('clear_screen', false).to_s == 'true'
          terminal_clear_display(string)
          [0, 0, false]
        else
          new_position, terminal_rows, screen_erased = fetch_cursor_position(table_size, position, options.fetch('screen_erased', false))
          display_string_at_position(new_position, string)
          [new_position, terminal_rows, screen_erased]
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

      def erase_screen
        puts("\e[2J")
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
