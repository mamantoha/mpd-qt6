require "json"

module MPDUI
  class Settings
    ORGANIZATION           = "mamantoha"
    DISPLAY_NAME           = "Crystal MPD"
    APPLICATION_ID         = "io.github.mamantoha.CrystalMPD"
    DESKTOP_ENTRY          = APPLICATION_ID
    CACHE_PREFIX           = "crystal-mpd"
    HOST_KEY               = "mpd/host"
    PORT_KEY               = "mpd/port"
    EXPANDED_INTERFACE_KEY = "ui/expanded_interface"
    SHOW_LIBRARY_KEY       = "ui/show_library"
    SHOW_MAIN_MENU_KEY     = "ui/show_main_menu"
    BLURRED_COVER_KEY      = "ui/blurred_cover_background"
    WINDOW_WIDTH_KEY       = "ui/expanded_window_width"
    WINDOW_HEIGHT_KEY      = "ui/expanded_window_height"
    WINDOW_MAXIMIZED_KEY   = "ui/expanded_window_maximized"
    SPLITTER_SIZES_KEY     = "ui/library_queue_splitter_sizes"
    LASTFM_ENABLED_KEY     = "lastfm/enabled"
    LASTFM_USERNAME_KEY    = "lastfm/username"
    LASTFM_SESSION_KEY     = "lastfm/session_key"

    property host : String
    property port : Int32
    property? expanded_interface : Bool
    property? show_library : Bool
    property? show_main_menu : Bool
    property? blurred_cover_background : Bool
    property expanded_window_width : Int32?
    property expanded_window_height : Int32?
    property? expanded_window_maximized : Bool
    property library_queue_splitter_sizes : Array(Int32)
    property? lastfm_enabled : Bool
    property lastfm_username : String
    property lastfm_session_key : String

    def initialize
      @host = "localhost"
      @port = 6600
      @expanded_interface = true
      @show_library = true
      @show_main_menu = true
      @blurred_cover_background = true
      @expanded_window_width = nil
      @expanded_window_height = nil
      @expanded_window_maximized = false
      @library_queue_splitter_sizes = [] of Int32
      @lastfm_enabled = false
      @lastfm_username = ""
      @lastfm_session_key = ""
    end

    def self.load : Settings
      store = settings_store
      settings = new
      settings.host = store.value(HOST_KEY, settings.host).as?(String) || settings.host
      settings.port = read_port(store, settings.port)
      settings.expanded_interface = read_bool(store, EXPANDED_INTERFACE_KEY, settings.expanded_interface?)
      settings.show_library = read_bool(store, SHOW_LIBRARY_KEY, settings.show_library?)
      settings.show_main_menu = read_bool(store, SHOW_MAIN_MENU_KEY, settings.show_main_menu?)
      settings.blurred_cover_background = read_bool(store, BLURRED_COVER_KEY, settings.blurred_cover_background?)
      settings.expanded_window_width = read_int(store, WINDOW_WIDTH_KEY)
      settings.expanded_window_height = read_int(store, WINDOW_HEIGHT_KEY)
      settings.expanded_window_maximized = read_bool(store, WINDOW_MAXIMIZED_KEY, settings.expanded_window_maximized?)
      settings.library_queue_splitter_sizes = read_int_array(store, SPLITTER_SIZES_KEY)
      settings.lastfm_enabled = read_bool(store, LASTFM_ENABLED_KEY, settings.lastfm_enabled?)
      settings.lastfm_username = store.value(LASTFM_USERNAME_KEY, settings.lastfm_username).as?(String) || settings.lastfm_username
      settings.lastfm_session_key = store.value(LASTFM_SESSION_KEY, settings.lastfm_session_key).as?(String) || settings.lastfm_session_key
      settings
    rescue
      new
    end

    def save : Nil
      store = self.class.settings_store
      store.set_value(HOST_KEY, @host)
      store.set_value(PORT_KEY, @port)
      store.set_value(EXPANDED_INTERFACE_KEY, @expanded_interface)
      store.set_value(SHOW_LIBRARY_KEY, @show_library)
      store.set_value(SHOW_MAIN_MENU_KEY, @show_main_menu)
      store.set_value(BLURRED_COVER_KEY, @blurred_cover_background)
      store.set_value(WINDOW_WIDTH_KEY, @expanded_window_width) if @expanded_window_width
      store.set_value(WINDOW_HEIGHT_KEY, @expanded_window_height) if @expanded_window_height
      store.set_value(WINDOW_MAXIMIZED_KEY, @expanded_window_maximized)
      store.set_value(SPLITTER_SIZES_KEY, @library_queue_splitter_sizes.to_json)
      store.set_value(LASTFM_ENABLED_KEY, @lastfm_enabled)
      store.set_value(LASTFM_USERNAME_KEY, @lastfm_username)
      store.set_value(LASTFM_SESSION_KEY, @lastfm_session_key)
      store.sync
    rescue
      nil
    end

    def self.settings_store : Qt6::QSettings
      Qt6::QSettings.for_application(ORGANIZATION, APPLICATION_ID)
    end

    private def self.read_port(store : Qt6::QSettings, default_port : Int32) : Int32
      case value = store.value(PORT_KEY, default_port)
      when Int32
        value
      when String
        value.to_i? || default_port
      else
        default_port
      end
    end

    private def self.read_int(store : Qt6::QSettings, key : String) : Int32?
      case value = store.value(key, nil)
      when Int32
        value
      when String
        value.to_i?
      end
    end

    private def self.read_int_array(store : Qt6::QSettings, key : String) : Array(Int32)
      value = store.value(key, "").as?(String)
      return [] of Int32 if value.nil? || value.empty?

      JSON.parse(value).as_a.compact_map(&.as_i?)
    rescue
      [] of Int32
    end

    private def self.read_bool(store : Qt6::QSettings, key : String, default_value : Bool) : Bool
      case value = store.value(key, default_value)
      when Bool
        value
      when String
        case value.downcase
        when "true", "1", "yes", "on"
          true
        when "false", "0", "no", "off"
          false
        else
          default_value
        end
      else
        default_value
      end
    end
  end
end
