module MPDUI
  class Settings
    ORGANIZATION           = "mamantoha"
    APPLICATION            = "mpd-qt6"
    HOST_KEY               = "mpd/host"
    PORT_KEY               = "mpd/port"
    EXPANDED_INTERFACE_KEY = "ui/expanded_interface"
    SHOW_LIBRARY_KEY       = "ui/show_library"

    property host : String
    property port : Int32
    property expanded_interface : Bool
    property show_library : Bool

    def initialize
      @host = "localhost"
      @port = 6600
      @expanded_interface = true
      @show_library = true
    end

    def self.load : Settings
      store = settings_store
      settings = new
      settings.host = store.value(HOST_KEY, settings.host).as?(String) || settings.host
      settings.port = read_port(store, settings.port)
      settings.expanded_interface = read_bool(store, EXPANDED_INTERFACE_KEY, settings.expanded_interface)
      settings.show_library = read_bool(store, SHOW_LIBRARY_KEY, settings.show_library)
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
      store.sync
    rescue
      nil
    end

    def self.settings_store : Qt6::QSettings
      Qt6::QSettings.for_application(ORGANIZATION, APPLICATION)
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
