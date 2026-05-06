require "qt6"
require "crystal_mpd"
require "digest/sha1"
require "./mpd_ui/version"
require "./mpd_ui/settings"
require "./mpd_ui/song"
require "./mpd_ui/playback_state"
require "./mpd_ui/event_bridge"
require "./mpd_ui/format_helpers"
require "./ext/lastfm/src/lastfm"
require "./ext/mpris/src/mpris"
require "./mpd_ui/mpd_connection"
require "./mpd_ui/app/mpris"
require "./mpd_ui/app/lastfm"
require "./mpd_ui/app/settings_dialog"
require "./mpd_ui/app/tray"
require "./mpd_ui/app/queue"
require "./mpd_ui/app/database"
require "./mpd_ui/app/about_dialog"
require "./mpd_ui/app/player"
require "./mpd_ui/app"

module MPDUI
  def self.run : Nil
    App.new.run
  end
end
