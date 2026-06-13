module MPDUI
  class LyricsService
    Log = ::Log.for("mpd_ui.lyrics")

    enum Status
      Loading
      Found
      NotFound
      Failed
    end

    record Update,
      request_id : Int32,
      status : Status,
      result : LyricsResult? = nil,
      error : String? = nil

    @generation = Atomic(Int32).new(0)

    def initialize(
      @client : LRCLIB::Client,
      @cache : LyricsCache,
      @dispatcher : Proc(Proc(Nil), Nil) = ->(callback : Proc(Nil)) { callback.call }
    )
    end

    def self.default(cache_name : String = Settings::CACHE_PREFIX, user_agent : String = Settings::DISPLAY_NAME) : self
      new(
        client: LRCLIB::Client.new(user_agent: user_agent),
        cache: LyricsCache.new(cache_name)
      )
    end

    def request(song : Song, &on_update : Update ->) : Int32
      request_id = @generation.add(1) + 1
      artist = song.artist
      title = song.display_title
      album = song.album?
      duration = song.duration.try(&.to_i)

      Log.info do
        "lyrics lookup requested: artist=#{artist.inspect} title=#{title.inspect} album=#{album.inspect} duration=#{duration.inspect} file=#{song.file.inspect}"
      end

      deliver(request_id, Update.new(request_id, Status::Loading), on_update)

      BackgroundRunner.run("mpd-ui-lyrics") do
        update =
          if entry = @cache.read(artist, title, duration)
            Log.info do
              "lyrics cache hit: status=#{entry.status} artist=#{artist.inspect} title=#{title.inspect} duration=#{duration.inspect}"
            end

            update_from_cache(request_id, entry)
          else
            Log.info do
              "lyrics cache miss: fetching from LRCLIB artist=#{artist.inspect} title=#{title.inspect} album=#{album.inspect} duration=#{duration.inspect}"
            end

            fetch_update(request_id, artist, title, album, duration)
          end

        deliver(request_id, update, on_update)
      rescue ex
        Log.warn { "lyrics lookup failed: #{ex.message || ex}" }
        deliver(request_id, Update.new(request_id, Status::Failed, error: ex.message || ex.to_s), on_update)
      end

      request_id
    end

    def cancel : Nil
      @generation.add(1)
    end

    private def update_from_cache(request_id : Int32, entry : LyricsCache::Entry) : Update
      if entry.found?
        Update.new(request_id, Status::Found, result: entry.to_result)
      else
        Update.new(request_id, Status::NotFound)
      end
    end

    private def fetch_update(request_id : Int32, artist : String, title : String, album : String?, duration : Int32?) : Update
      lyrics = fetch_with_fallbacks(artist, title, album, duration)

      unless lyrics
        Log.info do
          "lyrics not found from LRCLIB: artist=#{artist.inspect} title=#{title.inspect} album=#{album.inspect} duration=#{duration.inspect}"
        end

        @cache.write_not_found(artist, title, duration)
        return Update.new(request_id, Status::NotFound)
      end

      result = LyricsResult.from_lrclib(lyrics)
      Log.info do
        "lyrics found from LRCLIB: artist=#{lyrics.artist_name.inspect} title=#{lyrics.track_name.inspect} album=#{lyrics.album_name.inspect} synced_lines=#{result.synced_lines.size} plain=#{!result.plain_text.to_s.empty?} instrumental=#{result.instrumental}"
      end

      @cache.write_found(artist, title, duration, result)
      Update.new(request_id, Status::Found, result: result)
    end

    private def fetch_with_fallbacks(artist : String, title : String, album : String?, duration : Int32?) : LRCLIB::Lyrics?
      attempts = [] of Tuple(String, String?, Int32?)
      attempts << {"metadata", album, duration}
      attempts << {"without album", nil, duration} if album
      attempts << {"without album/duration", nil, nil} if album || duration

      attempts.each do |label, attempt_album, attempt_duration|
        Log.info do
          "lyrics LRCLIB attempt: #{label} artist=#{artist.inspect} title=#{title.inspect} album=#{attempt_album.inspect} duration=#{attempt_duration.inspect}"
        end

        lyrics = @client.get(
          artist_name: artist,
          track_name: title,
          album_name: attempt_album,
          duration: attempt_duration
        )

        return lyrics if lyrics
      end

      nil
    end

    private def deliver(request_id : Int32, update : Update, on_update : Update ->) : Nil
      return unless request_id == @generation.get

      @dispatcher.call(->{
        return unless request_id == @generation.get

        on_update.call(update)
      })
    end
  end
end
