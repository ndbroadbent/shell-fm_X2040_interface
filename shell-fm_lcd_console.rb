#!/usr/bin/ruby
# Simple script that displays the artist and title from shell-fm
# on a DSP-420 LCD screen.
# Scrolls any strings that are longer than their allowed lengths.
# If a string is scrolled, it is padded with 2 spaces to the beginning and end.
# (easier to read)

require 'rubygems'
require 'socket'
require File.join(File.dirname(__FILE__), 'lib', 'rubyX2040')
require File.join(File.dirname(__FILE__), 'lib', 'widget')

# shell.fm network interface config
IP = "localhost"
PORT = "54311"

Update_delay = 3.0    # Delay between shell.fm refreshes.
Scroll_delay = 0.5    # speed of artist and title scrolling

DisplayUpdateInterval = 0.05  # Poll for refreshes at this interval
BacklightTimeout      = 20.0  # Turn off the backlight after a delay

# Gets info from shell-fm
def shellfm_info
  # Gets the 'artist', 'title', and 'remaining seconds'
  cmd = "info %a||%l||%t||%R"
  t = TCPSocket.new(IP, PORT)
  t.print cmd + "\n"
  info = t.gets(nil).split("||")
  t.close

  return info.any? ? info : false
  rescue
    # On error, return false
    return false
end

def display_widget(widget)
  $p.message widget.render, widget.pos
end

def splash_screen
  $p.message "shell.fm LCD display", [2,1]
  $p.message "(c) Nathan Broadbent", [3,1]
  sleep 1
  $p.clear
end

def write_static_icons
  $p.write_char($p.icons["guitar"][:loc], [1,1])
  $p.write_char($p.icons["cd"][:loc],     [2,1])
  $p.write_char($p.icons["notes"][:loc],  [3,1])
end

# ----------- at_exit code ---------------------

at_exit {
  # When we quit, display a final "bye" message.
  $p.clear
  $p.backlight false
  $p.message "Bye!".center(20), [2,1]
}

# -------------- Script Start -------------------

# initialize DisplayUpdateIntervalPertelian display.
$p = Pertelian.new
# Load in some icons
Dir.glob(File.join(File.dirname(__FILE__), 'lcd_icons', '*.chr')).each_with_index do |filename, i|
  $p.load_char_from_file(filename, i+1)
end

# Display initial splash screen
splash_screen

# ------------------ Paused / Playing Screen --------------

# Set up widgets.
@artist_widget = Widget.new("", [1,3], 18)
@album_widget  = Widget.new("", [2,3], 18)
@title_widget  = Widget.new("", [3,3], 18)
@remain_widget = Widget.new("", [4,3], 6, :time)
# Variables to detect whether or not the stream is paused.
@status = :playing
@status_cache = nil  # cache for checking whether the status has changed from previous iteration
# An icon widget to show the track status
@status_widget = Widget.new("<play>", [4,1], 1, :icons)
@last_remain = 0

@key_info = Widget.new("  <next>:n <pause><play>:p <love>:l <stop>:s  ", [4,10], 10, :icons)

# Static icons for track info
write_static_icons

# Initialize a variable for timing out the backlight.
@backlight_time_left = BacklightTimeout

# ------------------- Stopped Screen -----------------------

@stopped_widget = Widget.new("<stop> Stopped.", [2,1], 20, :icons, :center)

# ------------------- Initialize threads -------------------

# Thread to periodically update our artist/title/remaining time hash and loop.
shellfm_refresh_thread = Thread.new {
  while true
    has_changed = false
    if data = shellfm_info
      [@artist_widget, @title_widget, @album_widget].zip(data[0,3]).each do |widget, value|
        # Reset widget scroll positions if their values have changed.
        if widget.value != value
          widget.value, widget.scroll_pos = value, 1
          has_changed = true
        end
      end
      # Set the remaining track time.
      @remain_widget.value = data[3]

      # Detect whether the stream is paused or not.
      currently_playing = (data[3].to_i > 0 && @last_remain != data[3])
      @last_remain = data[3]
      if @status == :playing
        unless currently_playing
          @status = :paused
          # Update the status icon to 'paused'
          @status_widget.value = "<pause>"
          has_changed = true
        end
      else
        if currently_playing
          @status = :playing
          @status_widget.value = "<play>"
          has_changed = true
        end
      end

    else  # else, if shellfm_info method returned false or nil, the track is stopped.
      if @status != :stopped
        @status = :stopped
        has_changed = true
      end
    end

    # Turn on the backlight if a value has changed.
    if has_changed
      @backlight_time_left = BacklightTimeout
    end

    sleep Update_delay
  end
}

# Thread to count down the remaining time between refreshes (if stream is playing)
countdown_remain_thread = Thread.new {
  while true
    @remain_widget.value = (@remain_widget.value.to_i - 1).to_s if @status == :playing
    sleep 1
  end
}

# Thread to scroll widgets.
scroll_thread = Thread.new {
  while true
    [@artist_widget, @title_widget, @album_widget, @key_info].each do |widget|
      widget.increment_scroll
    end
    sleep Scroll_delay
  end
}

# Loop to refresh widgets when needed. Also control backlight.
while true
  case @status
  when :playing, :paused
    if @status_cache == :stopped # Redraw static icons
      write_static_icons
      @status_cache = @status
    end
    [@artist_widget, @title_widget, @album_widget, @remain_widget, @key_info, @status_widget].each do |widget|
      display_widget(widget) if widget.needs_refresh
    end
  when :stopped
    if @status_cache != :stopped
      $p.clear
      display_widget(@stopped_widget)
      @status_cache = @status
    end
  end

  # Also timeout the backlight, if needed
  if @backlight_time_left > 0
    # If a thread has just set the backlight timeout, turn it on.
    $p.backlight true if @backlight_time_left == BacklightTimeout
    @backlight_time_left -= DisplayUpdateInterval
    if @backlight_time_left <= 0
      @backlight_time_left = 0.0
      $p.backlight false
    end
  end

  sleep DisplayUpdateInterval
end

