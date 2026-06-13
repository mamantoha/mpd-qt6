require "digest/sha1"
require "json"

module MPDUI
  class LyricsCache
    CACHE_KEY_VERSION = "v2"

    enum Status
      Found
      NotFound
    end

    struct Entry
      include JSON::Serializable

      getter status : Status
      getter synced_lines : Array(CachedLine)
      getter plain_text : String?
      getter instrumental : Bool
      getter cached_at : Int64

      def self.found(result : LyricsResult) : self
        new(
          status: Status::Found,
          synced_lines: result.synced_lines.map { |line| CachedLine.new(line) },
          plain_text: result.plain_text,
          instrumental: result.instrumental,
          cached_at: Time.utc.to_unix
        )
      end

      def self.not_found : self
        new(
          status: Status::NotFound,
          synced_lines: [] of CachedLine,
          plain_text: nil,
          instrumental: false,
          cached_at: Time.utc.to_unix
        )
      end

      def initialize(
        @status : Status,
        @synced_lines : Array(CachedLine),
        @plain_text : String?,
        @instrumental : Bool,
        @cached_at : Int64,
      )
      end

      def found? : Bool
        status.found?
      end

      def not_found? : Bool
        status.not_found?
      end

      def to_result : LyricsResult
        LyricsResult.new(
          synced_lines: synced_lines.map(&.to_line),
          plain_text: plain_text,
          instrumental: instrumental
        )
      end
    end

    struct CachedLine
      include JSON::Serializable

      getter time_ms : Int64
      getter text : String

      def initialize(line : LyricsLine)
        @time_ms = line.time.total_milliseconds.to_i64
        @text = line.text
      end

      def initialize(@time_ms : Int64, @text : String)
      end

      def to_line : LyricsLine
        LyricsLine.new(time_ms.milliseconds, text)
      end
    end

    def initialize(@cache_name : String)
    end

    def read(artist : String, title : String, duration : Int32?) : Entry?
      path = cache_path(artist, title, duration)
      return unless File.exists?(path)

      Entry.from_json(File.read(path))
    rescue ex
      Log.debug { "lyrics cache: failed to read #{path}: #{ex.message || ex}" }
      nil
    end

    def write_found(artist : String, title : String, duration : Int32?, result : LyricsResult) : Nil
      write(artist, title, duration, Entry.found(result))
    end

    def write_not_found(artist : String, title : String, duration : Int32?) : Nil
      write(artist, title, duration, Entry.not_found)
    end

    def delete(artist : String, title : String, duration : Int32?) : Nil
      File.delete(cache_path(artist, title, duration))
    rescue File::NotFoundError
      nil
    rescue ex
      Log.debug { "lyrics cache: failed to delete entry: #{ex.message || ex}" }
    end

    private def write(artist : String, title : String, duration : Int32?, entry : Entry) : Nil
      path = cache_path(artist, title, duration)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, entry.to_json)
    rescue ex
      Log.debug { "lyrics cache: failed to write entry: #{ex.message || ex}" }
    end

    private def cache_path(artist : String, title : String, duration : Int32?) : String
      File.join(cache_dir, "#{Digest::SHA1.hexdigest(cache_key(artist, title, duration))}.json")
    end

    private def cache_key(artist : String, title : String, duration : Int32?) : String
      [CACHE_KEY_VERSION, artist.strip.downcase, title.strip.downcase, duration.to_s].join("\0")
    end

    private def cache_dir : String
      cache_home = ENV["XDG_CACHE_HOME"]? || File.join(ENV["HOME"]? || Dir.tempdir, ".cache")
      File.join(cache_home, @cache_name, "lyrics")
    end
  end
end
