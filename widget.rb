# Widget class to display blocks of text at arbitrary positions, with scrolling.

class Widget
  attr_accessor :pos, :length, :scroll_pos, :needs_refresh
  attr_reader :value

  def initialize(value, pos, length=20, format=:none, align=:ljust)
    raise "Invalid 'align' param!" unless [:ljust, :rjust, :center].include?(align)
    @value, @pos, @length, @format, @align = value, pos, length, format, align
    @scroll_pos = 1
    # After widget is first initialized, it needs to be displayed.
    @needs_refresh = true
  end

  def value=(value)
    # If we are setting the widget string, the display needs to be refreshed.
    @value = value
    @needs_refresh = true
  end

  def padded(str)
    # Give the string a buffer padding of 2 spaces on either side, if we are going to scroll it.
    "  #{str}  "
  end
  def format_as_time(str)
    min, sec = (str.to_i / 60), (str.to_i % 60)
    min, sec = 0, 0 if min < 0
    time = "%02d:%02d" % [min, sec]
  end

  def increment_scroll
    # Only increment the scroll pos if we need to.
    if @value.size > @length
      @scroll_pos += 1
      @scroll_pos = 1 if padded(@value)[@scroll_pos-1, padded(@value).size].size < @length
      @needs_refresh = true    # need to refresh display.
      true
    end
  end

  def render
    # If we are rendering, it means we no longer need to refresh.
    @needs_refresh = false

    string = case @format
    when :time
      format_as_time(@value)
    else
      @value
    end

    # Returns the display string for the widget - padded and scrolled.
    if string.size > @length
      padded(string)[@scroll_pos-1, @length]
    else
      string.send(@align, @length)
    end
  end

end

