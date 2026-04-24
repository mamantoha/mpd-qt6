module MPDUI
  class Settings
    ORGANIZATION = "mamantoha"
    APPLICATION  = "mpd-qt6"
    HOST_KEY     = "mpd/host"
    PORT_KEY     = "mpd/port"

    property host : String
    property port : Int32

    def initialize
      @host = "localhost"
      @port = 6600
    end

    def self.load : Settings
      store = settings_store
      settings = new
      settings.host = store.value(HOST_KEY, settings.host).as?(String) || settings.host
      settings.port = read_port(store, settings.port)
      settings
    rescue
      new
    end

    def save : Nil
      store = self.class.settings_store
      store.set_value(HOST_KEY, @host)
      store.set_value(PORT_KEY, @port)
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
  end
end
