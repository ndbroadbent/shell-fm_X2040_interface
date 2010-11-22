#!/usr/bin/ruby
# Simple script that displays the artist and title from shell-fm
# on a DSP-420 LCD screen.
# Scrolls any strings that are longer than their allowed lengths.
# If a string is scrolled, it is padded with 2 spaces to the beginning and end.
# (easier to read)

require 'rubygems'
require 'socket'
require 'yaml'
require File.join(File.dirname(__FILE__), 'lib', 'rubyX2040')
require File.join(File.dirname(__FILE__), 'lib', 'widget')

# Load config.
config = YAML.load_file(File.join(File.dirname(__FILE__), "config.yml"))
Host   = config["host"]
Port   = config["port"]

Update_delay = 3.0    # Delay between shell.fm refreshes.
Scroll_delay = 0.5    # speed of artist and title scrolling

DisplayUpdateInterval = 0.05  # Poll for refreshes at this interval
BacklightTimeout      = 20.0  # Turn off the backlight after a delay

# Gets info from shell-fm
def shellfm_info
  # Gets the 'artist', 'title', and 'remaining seconds'
  cmd = "info %a||%l||%t||%R"
  t = TCPSocket.new(Host, Port)
  t.print cmd + "\n"
  info = t.gets(nil).split("||")
  t.close

  return info.any? ? info : false
  rescue
    # On error, return false
    return false
end
# Sends a cmd to the shellfm network interface.
def shellfmcmd(cmd)
  t = TCPSocket.new(Host, Port)
  t.print cmd + "\n"
  info = t.gets(nil)
  t.close
  return true
  rescue
    false
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

# Evo T20 is synced to UTC. HK time is UTC +8
def hk_time
  Time.now + 8*60*60
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

def main_widgets
  [@artist_widget, @title_widget, @album_widget, @remain_widget, @key_info, @status_widget]
end

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
      main_widgets.each {|w| w.needs_refresh = true } # Refresh all of the widgets, just in case.
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

# Thread for alarms (trigger actions at configured times.)
alarm_thread = Thread.new {
  # Wait for status to initialize
  sleep Update_delay * 3
  while true
    time = hk_time
    # Load the alarms file each minute. This is the easiest way to dynamically configure them
    # via the shellfm sinatra app.
    if alarms = YAML.load_file(File.join(File.dirname(__FILE__), "alarms.yml"))
      alarms.each do |alarm|
        if alarm["days_of_week"].include?(time.wday)
          alarm_time = DateTime.parse(alarm["time"])
          if alarm_time.hour == time.hour && alarm_time.min == time.min
            # Alarm matches, trigger action.
            case alarm["action"]
            when "play"
              # Volume 0 (because we may have to unpause for a little while)
              shellfmcmd("volume 0")
              # If station is paused, we must unpause it first.
              shellfmcmd("pause") if @status == :paused
              shellfmcmd("play lastfm://#{alarm["station"]}")
              shellfmcmd("skip") unless @status == :stopped # skip 'delay' unless status is stopped
              shellfmcmd("volume 100") # Reset volume to 100%
            when "pause"
              shellfmcmd("pause") if @status == :playing
            when "stop"
              shellfmcmd("volume 0")
              # If station is paused, we must unpause it first.
              shellfmcmd("pause") if @status == :paused
              shellfmcmd("stop")
              shellfmcmd("volume 100") # Reset volume to 100%
            end
          end
        end
      end
    end
    # Wait until the next minute, then loop.
    while hk_time.min == time.min
      sleep 5
    end
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
    main_widgets.each do |widget|
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

