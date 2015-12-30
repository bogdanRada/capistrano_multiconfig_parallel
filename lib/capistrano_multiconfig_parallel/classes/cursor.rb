require 'io/console'
module CapistranoMulticonfigParallel
  # class used to fetch cursor position before displaying terminal table
  class Cursor
    class << self

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
        position = options.fetch(:position, nil)
        if options.fetch(:terminal_clear, nil).to_s == 'true'
          terminal_clear
          puts string
        else
          position_cursor(position[:row], position[:column]) if position.present?
          reputs string
        end
      end

      def reputs( str = '' )
        puts "\e[0K" + str
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
