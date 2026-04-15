require "qt6"
require "crystal_mpd"
require "./mpd_ui/version"
require "./mpd_ui/settings"
require "./mpd_ui/app"

module MPDUI
  def self.run : Nil
    App.new.run
  end
end

MPDUI.run
