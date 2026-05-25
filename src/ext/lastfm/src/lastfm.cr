require "digest/md5"
require "http/client"
require "json"
require "uri"

# Small Last.fm client and scrobbling state machine.
#
# This module is intentionally independent from the Qt/MPD application. The host
# application owns credentials, settings, and playback state, then feeds plain
# song/status snapshots into `Scrobbler`.
module LastFM
  Log = ::Log.for("lastfm")

  API_URL = "https://ws.audioscrobbler.com/2.0/"

  # Raised when Last.fm rejects a request or the HTTP/JSON layer fails.
  class Error < Exception
  end

  # Persistent user authorization returned by `auth.getMobileSession`.
  #
  # Applications should store the session key instead of keeping the user's
  # password. Future API writes use this key in the `sk` parameter.
  struct Session
    getter username : String
    getter key : String

    def initialize(@username : String, @key : String)
    end
  end

  # Normalized track metadata passed to Last.fm.
  #
  # `timestamp` is the Unix time when playback started. Last.fm uses that value
  # as the scrobble time, so it must stay stable while the song is playing.
  struct Track
    getter id : String
    getter artist : String
    getter title : String
    getter album : String?
    getter duration : Int32
    getter track_number : Int32?
    getter timestamp : Int64

    def initialize(@id : String, @artist : String, @title : String, @album : String?, @duration : Int32, @track_number : Int32?, @timestamp : Int64)
    end

    def scrobbleable? : Bool
      !artist.strip.empty? && !title.strip.empty? && duration > 30
    end

    # Last.fm's standard point for submitting a scrobble: half the track length
    # or four minutes, whichever happens first.
    def threshold : Float64
      {duration / 2.0, 240.0}.min
    end
  end

  # Disk representation for scrobbles that failed because the network or
  # Last.fm was unavailable.
  struct PendingScrobble
    include JSON::Serializable

    getter artist : String
    getter title : String
    getter album : String?
    getter duration : Int32
    getter track_number : Int32?
    getter timestamp : Int64

    def initialize(track : Track)
      @artist = track.artist
      @title = track.title
      @album = track.album
      @duration = track.duration
      @track_number = track.track_number
      @timestamp = track.timestamp
    end

    def to_track : Track
      Track.new("#{artist}\u0000#{title}\u0000#{timestamp}", artist, title, album, duration, track_number, timestamp)
    end
  end

  # Thin wrapper around the Last.fm REST API.
  #
  # The API key and shared secret are passed in from the application so this file
  # can later become a reusable shard without embedding one app's credentials.
  class Client
    def initialize(@api_key : String, @shared_secret : String)
    end

    # Exchanges a username/password for a reusable session key.
    #
    # This is intended for one-time setup from an application settings dialog.
    def mobile_session(username : String, password : String) : Session
      params = {
        "method"   => "auth.getMobileSession",
        "username" => username,
        "password" => password,
        "api_key"  => @api_key,
      }

      json = request(sign(params))
      session = json["session"]?
      key = session.try(&.["key"]?.try(&.as_s?)).to_s
      name = session.try(&.["name"]?.try(&.as_s?)).to_s
      raise Error.new("Last.fm did not return a session key") if key.empty?

      Session.new(name.empty? ? username : name, key)
    end

    # Publishes the current song to Last.fm's "Scrobbling now" UI.
    def update_now_playing(track : Track, session_key : String) : Nil
      params = {
        "method"   => "track.updateNowPlaying",
        "artist"   => track.artist,
        "track"    => track.title,
        "duration" => track.duration.to_s,
        "api_key"  => @api_key,
        "sk"       => session_key,
      }

      if album = track.album
        params["album"] = album
      end

      if track_number = track.track_number
        params["trackNumber"] = track_number.to_s
      end

      request(sign(params))
    end

    # Submits a completed play. This is separate from `update_now_playing`;
    # Last.fm may show both while the same song is still playing.
    def scrobble(track : Track, session_key : String) : Nil
      params = {
        "method"       => "track.scrobble",
        "artist[0]"    => track.artist,
        "track[0]"     => track.title,
        "timestamp[0]" => track.timestamp.to_s,
        "duration[0]"  => track.duration.to_s,
        "api_key"      => @api_key,
        "sk"           => session_key,
      }

      if album = track.album
        params["album[0]"] = album
      end

      if track_number = track.track_number
        params["trackNumber[0]"] = track_number.to_s
      end

      request(sign(params))
    end

    private def request(params : Hash(String, String)) : JSON::Any
      params = params.dup
      params["format"] = "json"

      # Last.fm write methods expect form-encoded POST data. The response can
      # still be JSON by passing `format=json`.
      response = HTTP::Client.post(API_URL, form: params)
      json = JSON.parse(response.body)

      if response.status_code >= 400 || json["error"]?
        code = json["error"]?.try(&.to_s)
        message = json["message"]?.try(&.as_s?) || "HTTP #{response.status_code}"
        detail = code ? "#{message} (code #{code})" : message
        raise Error.new(detail)
      end

      json
    rescue ex : Error
      raise ex
    rescue ex
      raise Error.new(ex.message || ex.to_s)
    end

    # Last.fm request signing concatenates sorted key/value pairs plus the shared
    # secret and sends the MD5 as `api_sig`.
    private def sign(params : Hash(String, String)) : Hash(String, String)
      signed = params.dup

      source = String.build do |io|
        params.keys.sort!.each do |key|
          next if key == "format" || key == "callback"

          io << key << params[key]
        end
        io << @shared_secret
      end

      signed["api_sig"] = Digest::MD5.hexdigest(source)
      signed
    end
  end

  # Tracks playback progress and decides when Last.fm API calls should happen.
  #
  # The host application calls `update` whenever playback state or elapsed time
  # changes. The scrobbler handles duplicate prevention, now-playing updates,
  # threshold-based scrobbling, and retrying failed scrobbles.
  #
  # Example:
  #
  # ```
  # client = LastFM::Client.new(api_key, shared_secret)
  # session = client.mobile_session(username, password)
  #
  # scrobbler = LastFM::Scrobbler.new(
  #   "my-player",
  #   -> { settings.scrobbling_enabled? },
  #   -> { session.key },
  #   client
  # )
  #
  # scrobbler.update(current_song_metadata, "play", elapsed_seconds, duration_seconds)
  # scrobbler.update(current_song_metadata, "pause", elapsed_seconds, duration_seconds)
  # scrobbler.update(nil, "stop", 0.0, 0.0)
  # ```
  class Scrobbler
    @mutex = Mutex.new
    @current : Track?
    @last_elapsed : Float64 = 0.0
    @now_playing_sent : Bool = false
    @scrobble_sent : Bool = false
    @flushing_queue : Bool = false
    @queue : Array(PendingScrobble)

    # `enabled` and `session_key` are callbacks so the app can change settings
    # without rebuilding this object for every update.
    def initialize(@cache_name : String, @enabled : -> Bool, @session_key : -> String, @client : Client)
      @queue = load_queue
    end

    # Main entrypoint from the player.
    #
    # Sends now-playing when a new track starts and sends the scrobble once the
    # Last.fm threshold is reached. This mirrors common desktop player behavior,
    # including Cantata's timing.
    def update(song : Hash(String, String)?, state : String, elapsed : Float64, duration : Float64) : Nil
      unless active?
        reset
        return
      end

      if state == "stop" || song.nil?
        reset
        return
      end

      track = build_track(song, elapsed, duration)
      unless track && track.scrobbleable?
        reset
        return
      end

      changed = update_current_track(track, elapsed)
      return unless state == "play"

      send_now_playing(track) if changed
      flush_queue
      send_scrobble(track) if elapsed >= track.threshold
    end

    # Updates local track bookkeeping without implying that playback is active.
    # This lets pause events preserve the current song and elapsed position while
    # preventing paused playback from triggering now-playing or scrobble writes.
    private def update_current_track(track : Track, elapsed : Float64) : Bool
      @mutex.synchronize do
        previous = @current
        restarted = previous && previous.id == track.id && elapsed + 2.0 < @last_elapsed
        if previous.nil? || previous.id != track.id || restarted
          @current = track
          @last_elapsed = elapsed
          @now_playing_sent = false
          @scrobble_sent = false
          true
        else
          @last_elapsed = elapsed
          false
        end
      end
    end

    # Convenience wrapper used by settings UIs.
    def authenticate(username : String, password : String) : Session
      @client.mobile_session(username, password)
    end

    private def active? : Bool
      @enabled.call && !@session_key.call.empty?
    end

    private def reset : Nil
      @mutex.synchronize do
        @current = nil
        @last_elapsed = 0.0
        @now_playing_sent = false
        @scrobble_sent = false
      end
    end

    # Converts loose player metadata into the stable Last.fm `Track` shape.
    # Tracks without real artist/title metadata are ignored instead of deriving
    # scrobbles from file names.
    private def build_track(song : Hash(String, String), elapsed : Float64, duration : Float64) : Track?
      artist = song["Artist"]?.try(&.strip).presence
      title = song["Title"]?.try(&.strip).presence

      return if !artist || !title

      duration_seconds = (duration.positive? ? duration : song_duration(song)).round.to_i
      timestamp = Time.utc.to_unix - elapsed.round.to_i
      id = song["Id"]? || song["file"]? || "#{artist}\u0000#{title}"
      Track.new(id, artist, title, song["Album"]?, duration_seconds, metadata_number(song, "Track"), timestamp)
    end

    private def song_duration(song : Hash(String, String)) : Float64
      song["duration"]?.try(&.to_f?) || song["Time"]?.try(&.to_f?) || 0.0
    end

    private def metadata_number(song : Hash(String, String), key : String) : Int32?
      value = song[key]? || return
      part = value.split('/').first.strip
      part.to_i?
    end

    # Runs now-playing in a background thread so UI playback updates do not wait
    # on the network.
    private def send_now_playing(track : Track) : Nil
      should_send = @mutex.synchronize do
        next false if @now_playing_sent

        @now_playing_sent = true
        true
      end

      return unless should_send

      run_background("lastfm-now-playing") do
        @client.update_now_playing(track, @session_key.call)
        Log.debug { "updated now playing: #{track.artist} - #{track.title}" }
      rescue ex
        Log.debug { "failed to update now playing: #{ex.message || ex}" }
      end
    end

    # Runs scrobbling in a background thread and caches the track if submission
    # fails, so offline listening can be retried later.
    private def send_scrobble(track : Track) : Nil
      should_send = @mutex.synchronize do
        next false if @scrobble_sent

        @scrobble_sent = true
        true
      end

      return unless should_send

      run_background("lastfm-scrobble") do
        @client.scrobble(track, @session_key.call)
        Log.info { "scrobbled: #{track.artist} - #{track.title}" }
      rescue ex
        Log.info { "failed to scrobble #{track.artist} - #{track.title}: #{ex.message || ex}" }
        cache_failed_scrobble(track)
      end
    end

    # Attempts to replay cached scrobbles. Only one flush runs at a time because
    # playback progress can call `update` frequently.
    private def flush_queue : Nil
      pending = @mutex.synchronize do
        next [] of PendingScrobble if @flushing_queue
        next [] of PendingScrobble if @queue.empty?

        @flushing_queue = true
        @queue.dup
      end

      return if pending.empty?

      run_background("lastfm-flush") do
        failed = [] of PendingScrobble
        pending.each do |item|
          track = item.to_track
          begin
            @client.scrobble(track, @session_key.call)
          rescue
            failed << item
          end
        end

        @mutex.synchronize do
          @queue = failed
          @flushing_queue = false
        end
        save_queue
      rescue ex
        Log.debug { "failed to flush scrobble cache: #{ex.message || ex}" }
        @mutex.synchronize { @flushing_queue = false }
      end
    end

    private def run_background(name : String, &block : ->) : Nil
      run_background(name, block)
    end

    private def run_background(name : String, block : Proc(Nil)) : Nil
      {% if flag?(:execution_context) %}
        Fiber::ExecutionContext::Isolated.new(name) { block.call }
      {% else %}
        Thread.new(name: name) { block.call }
      {% end %}
    end

    private def cache_failed_scrobble(track : Track) : Nil
      @mutex.synchronize do
        item = PendingScrobble.new(track)
        @queue << item unless @queue.any? { |queued| queued.timestamp == item.timestamp && queued.artist == item.artist && queued.title == item.title }
      end

      save_queue
    end

    private def load_queue : Array(PendingScrobble)
      path = queue_path

      return [] of PendingScrobble unless File.exists?(path)

      Array(PendingScrobble).from_json(File.read(path))
    rescue
      [] of PendingScrobble
    end

    private def save_queue : Nil
      path = queue_path
      Dir.mkdir_p(File.dirname(path))
      queue = @mutex.synchronize { @queue.dup }
      File.write(path, queue.to_json)
    rescue ex
      Log.debug { "failed to save scrobble cache: #{ex.message || ex}" }
    end

    private def queue_path : String
      cache_home = ENV["XDG_CACHE_HOME"]? || File.join(ENV["HOME"]? || Dir.tempdir, ".cache")
      File.join(cache_home, @cache_name, "lastfm_scrobbles.json")
    end
  end
end
