require "qt6"
require "crystal_mpd"
require "./mpd_ui/version"
require "./mpd_ui/settings"
require "./mpd_ui/event_bridge"
require "./mpd_ui/app/settings_dialog"
require "./mpd_ui/app/tray"
require "./mpd_ui/app/queue"
require "./mpd_ui/app/database"
require "./mpd_ui/app/settings_dialog_action"
require "./mpd_ui/app/about_dialog"
require "./mpd_ui/app/player"
require "./mpd_ui/app/mpd_connection"
require "./mpd_ui/app"

module MPDUI
  def self.run : Nil
    App.new.run
  end
end
