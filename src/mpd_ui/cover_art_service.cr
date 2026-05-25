module MPDUI
  class CoverArtService
    record Result,
      uri : String,
      bytes : Bytes?,
      metadata : Hash(String, String)

    def initialize(@host : String, @port : Int32, @cache_name : String)
    end

    def fetch(uri : String, song : Song? = nil) : Result
      if bytes = read_cache(cache_path(uri, song))
        return Result.new(uri, bytes, metadata(bytes))
      end

      client = MPD::Client.new(@host, @port)

      response = begin
        client.readpicture(uri)
      rescue
        nil
      end

      response ||= begin
        client.albumart(uri)
      rescue
        nil
      end

      return Result.new(uri, nil, {} of String => String) unless response

      metadata, io = response
      io.rewind
      bytes = io.to_slice.dup
      write_cache(cache_path(uri, song), bytes)
      Result.new(uri, bytes, metadata)
    rescue
      Result.new(uri, nil, {} of String => String)
    ensure
      client.try(&.disconnect)
    end

    private def cache_path(uri : String, song : Song?) : String
      File.join(cache_dir, "#{Digest::SHA1.hexdigest(cache_key(uri, song))}.cover")
    end

    private def cache_key(uri : String, song : Song?) : String
      source = ["mpd", @host, @port.to_s]
      return (source + ["file", uri]).join("\0") unless song

      album = song.album? || ""
      return (source + ["file", uri]).join("\0") if album.empty?

      artist = song.album_artist? || song.artist? || ""
      date = song.date || ""
      (source + ["album", artist, album, date]).join("\0")
    end

    private def cache_dir : String
      cache_home = ENV["XDG_CACHE_HOME"]? || File.join(ENV["HOME"]? || Dir.tempdir, ".cache")
      File.join(cache_home, @cache_name, "covers")
    end

    private def read_cache(path : String) : Bytes?
      return unless File.exists?(path)

      File.read(path).to_slice.dup
    rescue ex
      Log.debug { "cover art: failed to read cache #{path}: #{ex.message || ex}" }
      nil
    end

    private def write_cache(path : String, bytes : Bytes) : Nil
      Dir.mkdir_p(File.dirname(path))
      File.write(path, bytes)
    rescue ex
      Log.debug { "cover art: failed to write cache #{path}: #{ex.message || ex}" }
    end

    private def metadata(bytes : Bytes) : Hash(String, String)
      type = MimeMagic.by_magic(bytes)
      type ? {"type" => type} : {} of String => String
    end
  end
end
