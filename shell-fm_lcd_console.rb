#!/usr/bin/ruby
# Simple script that displays the artist and title from shell-fm
# on a DSP-420 LCD screen.
# Scrolls any strings that are longer than their allowed lengths.
# If a string is scrolled, it is padded with 2 spaces to the beginning and end.
# (easier to read)



require 'rubygems'
require 'socket'
require File.join(File.dirname(__FILE__), 'rubyX2040')
require File.join(File.dirname(__FILE__), 'widget')

# shell.fm network interface config
IP = "localhost"
PORT = "54311"

Update_delay = 4.0     # Delay between shell.fm refreshes.
Scroll_delay = 0.5   # speed of artist and title scrolling

# Gets info from shell-fm
def shellfm_info
  # Gets the 'artist', 'title', and 'remaining seconds'
  cmd = "info %a||%l||%t||%R"
  t = TCPSocket.new(IP, PORT)
  t.print cmd + "\n"
  info = t.gets(nil).split("||")
  t.close
  return info
  rescue
    # On error, returns blank for everything
    return [""]*4
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

# ----------- at_exit code ---------------------

at_exit {
  # When we quit, display a final "bye" message.
  $p.clear
  $p.message "Bye!".center(20), [2,1]
}

# -------------- Script Start -------------------

# initialize Pertelian display.
$p = Pertelian.new
# Load in some icons
Dir.glob(File.join(File.dirname(__FILE__), 'lcd_icons', '*.chr')).each_with_index do |filename, i|
  $p.load_char_from_file(filename, i+1)
end

# Display initial splash screen
splash_screen

# Get our first reading from shellfm and initialize artist and title arrays,
# and write the first data to the lcd.
# Also set up buffers to keep track of value changes.
artist, title, album, remain = shellfm_info
@artist = Widget.new(artist, [1,3], 18)
@album  = Widget.new(album,  [2,3], 18)
@title  = Widget.new(title,  [3,3], 18)
@remain = Widget.new(remain, [4,3], 7, :time)

# Display icons
$p.write_char($p.icons["guitar"][:loc], [1,1])
$p.write_char($p.icons["cd"][:loc],     [2,1])
$p.write_char($p.icons["notes"][:loc],  [3,1])
$p.write_char($p.icons["play"][:loc],   [4,1])

# ------------------- Initialize threads -------------------

# Thread to periodically update our artist/title/remaining time hash and loop.
shellfm_refresh_thread = Thread.new {
  while true
    [@artist, @title, @album, @remain].zip(shellfm_info).each do |widget, value|
      # Reset widget scroll positions if their values have changed.
      widget.value, widget.scroll_pos = value, 1 if widget.value != value
    end
    sleep Update_delay
  end
}

# Thread to count down the remaining time between refreshes.
countdown_remain_thread = Thread.new {
  while true
    @remain.value = (@remain.value.to_i - 1).to_s
    sleep 1
  end
}

# Thread to scroll track and artist.
scroll_thread = Thread.new {
  while true
    [@artist, @title, @album, @remain].each do |widget|
      widget.increment_scroll
    end
    sleep Scroll_delay
  end
}

# Loop to refresh widgets when needed.
while true
  [@artist, @title, @album, @remain].each do |widget|
    display_widget(widget) if widget.needs_refresh
  end
  sleep 0.05
end

