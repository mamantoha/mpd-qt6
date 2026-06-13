require "http/client"
require "json"
require "uri"

# Minimal LRCLIB API client.
#
# The module is intentionally independent from Garnetune application code. The
# host application provides song metadata, calls `Client#get`, and decides how
# to cache and display the returned lyrics.
module LRCLIB
  API_URL = "https://lrclib.net"

  # Raised when LRCLIB or the HTTP/JSON layer returns an unexpected response.
  class Error < Exception
  end

  # A single timestamped lyric line parsed from LRCLIB's LRC-style synced text.
  struct SyncedLine
    getter time : Time::Span
    getter text : String

    def initialize(@time : Time::Span, @text : String)
    end
  end

  # Normalized lyrics response returned by LRCLIB.
  struct Lyrics
    getter id : Int32?
    getter track_name : String
    getter artist_name : String
    getter album_name : String?
    getter duration : Int32?
    getter instrumental : Bool
    getter plain_lyrics : String?
    getter synced_lyrics : String?

    def initialize(
      @id : Int32?,
      @track_name : String,
      @artist_name : String,
      @album_name : String?,
      @duration : Int32?,
      @instrumental : Bool,
      @plain_lyrics : String?,
      @synced_lyrics : String?,
    )
    end

    def self.from_json(json : String) : self
      object = JSON.parse(json)

      new(
        id: object["id"]?.try(&.as_i?),
        track_name: object["trackName"]?.try(&.as_s?) || object["name"]?.try(&.as_s?) || "",
        artist_name: object["artistName"]?.try(&.as_s?) || "",
        album_name: object["albumName"]?.try(&.as_s?),
        duration: object["duration"]?.try(&.as_i?),
        instrumental: object["instrumental"]?.try(&.as_bool?) || false,
        plain_lyrics: object["plainLyrics"]?.try(&.as_s?),
        synced_lyrics: object["syncedLyrics"]?.try(&.as_s?)
      )
    end

    def synced_lines : Array(SyncedLine)
      synced_lyrics.to_s.each_line.compact_map do |line|
        SyncedLine.parse?(line)
      end.to_a
    end

    def has_lyrics? : Bool
      !plain_lyrics.to_s.strip.empty? || !synced_lyrics.to_s.strip.empty?
    end
  end

  struct SyncedLine
    TIMESTAMP = /\A\[(\d+):(\d+(?:\.\d+)?)\](.*)\z/

    def self.parse?(line : String) : self?
      match = TIMESTAMP.match(line)
      return unless match

      minutes = match[1].to_i
      seconds = match[2].to_f
      text = match[3].strip

      new((minutes * 60 + seconds).seconds, text)
    end
  end

  # Thin wrapper around LRCLIB's HTTP API.
  class Client
    def initialize(@base_url : String = API_URL, @user_agent : String = "Garnetune")
    end

    # Finds lyrics for a track. Returns `nil` when LRCLIB has no match.
    #
    # `duration` is optional but improves match quality when available.
    def get(artist_name : String, track_name : String, album_name : String? = nil, duration : Int32? = nil) : Lyrics?
      params = URI::Params.build do |form|
        form.add "artist_name", artist_name
        form.add "track_name", track_name
        form.add "album_name", album_name if album_name
        form.add "duration", duration.to_s if duration
      end

      response = HTTP::Client.get(uri("/api/get", params), headers: headers)
      return nil if response.status_code == 404

      unless response.success?
        raise Error.new("LRCLIB request failed: HTTP #{response.status_code}")
      end

      Lyrics.from_json(response.body)
    rescue ex : JSON::ParseException
      raise Error.new("LRCLIB returned invalid JSON: #{ex.message}")
    rescue ex : IO::Error | Socket::Error
      raise Error.new("LRCLIB request failed: #{ex.message}")
    end

    private def uri(path : String, query : String) : URI
      uri = URI.parse(@base_url)
      uri.path = path
      uri.query = query
      uri
    end

    private def headers : HTTP::Headers
      HTTP::Headers{"User-Agent" => @user_agent}
    end
  end
end
