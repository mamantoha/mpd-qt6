require "json"

module MPDUI
  class Settings
    property host : String
    property port : Int32

    def initialize
      @host = "localhost"
      @port = 6600
    end

    def self.settings_path : String
      config_home = ENV["XDG_CONFIG_HOME"]?
      if config_home && !config_home.empty?
        return File.join(config_home, "mpd-qt6", "settings.json")
      end

      home = ENV["HOME"]? || "."
      File.join(home, ".config", "mpd-qt6", "settings.json")
    end

    def self.load : Settings
      path = settings_path
      return new unless File.exists?(path)

      parsed = JSON.parse(File.read(path)).as_h
      settings = new
      settings.host = parsed["host"]?.try(&.as_s) || settings.host
      settings.port = parsed["port"]?.try(&.as_i) || settings.port
      settings
    rescue
      new
    end

    def save : Nil
      path = self.class.settings_path
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      File.write(path, {host: @host, port: @port}.to_json)
    rescue
      nil
    end
  end
end
