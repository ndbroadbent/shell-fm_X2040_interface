# Ruby interface to the Pertelian X2040 LCD Display

require 'rubygems'
require 'serialport'

class Pertelian
  attr_accessor :icons

  def initialize(tty='/dev/ttyUSB0')
    @sp = SerialPort.new tty

    @write_delay = 0.001  # Number of seconds to wait between character bytes.
    @instruction_delay = 0.01  # Number of seconds to wait between instruction bytes.
    @row_width = 20  # Number of characters that will fit on a line.
    @row_offsets = [0x00, 0x40, 0x14, 0x54]  # Offsets for ordering rows correctly.

    setup
    @icons = {}
  end

  def setup
    # Set up the display.
    # Function set with 8-bit data length, 2 lines, and 5x7 dot size.
    # Entry mode set; increment cursor direction; do not automatically shift.
    # Cursor/display shift; cursor move.
    # Display On; cursor off; do not blink.
    "\x38\x06\x10\x0C\x01".split('').each do |byte|
      send_instruction(byte)
    end
  end

  def set_cursor(pos)
    unless pos.is_a? Array
      # Global pos (1 - 80)
      row = 1
      while pos > 20
        row += 1
        pos -= 20
      end
      pos = [row, pos]
    end
    # As an array of [row (1 - 4), column (1 - 20)]
    send_bytes ["\xfe", (0b10000000 + @row_offsets[pos[0]-1] + pos[1]-1).chr]
  end

  def send_bytes(bytes, delay=@write_delay)
    # Send a stream of bytes to the Pertelian.
    # Also, sleep for delay seconds between sending each byte.
    bytes.each do |byte|
      @sp.write byte
      sleep delay
    end
  end

  def send_instruction(byte)
    # Send an instruction byte to the Pertelian.
    send_bytes ["\xfe", byte], @instruction_delay
  end

  def power(on)
    # Turn the power on or off.
    on ? send_instruction("\x0c") : send_instruction("\x08")
  end

  def backlight(on)
    # Turn the backlight on or off.
    on ? send_instruction("\x03") : send_instruction("\x02")
  end

  def clear
    # Clear the display.
    send_instruction("\x01")
  end

  def message(msg, pos=nil)
    set_cursor(pos) if pos
    # Display a message.
    send_bytes(msg.split(''))
  end

  def load_char(mem_loc, char_data)
    send_bytes ["\xfe", (0b01000000 + (8 * (mem_loc - 1))).chr]
    send_bytes char_data
  end

  def write_char(mem_loc, pos=nil)
    set_cursor(pos) if pos
    send_bytes [(mem_loc-1).chr]
  end

  def load_char_from_file(filename, mem_loc, char_index=1)
    rows = File.open(filename, 'r').read.split("-----\n")[char_index-1].split("\n")
    # Map binary data based on presence of '#' character.
    data = rows.map{|row| row.ljust(5).split('').inject(0b00000){|r, c| r = r << 1; r += 1 if c == "#" || c == "*"; r }.chr}
    load_char(mem_loc, data)
    # Save icon memory index and data.
    @icons[File.basename(filename, ".chr")] = {:loc => mem_loc, :data => data}
  end
end

