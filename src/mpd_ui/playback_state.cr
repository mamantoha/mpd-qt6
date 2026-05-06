module MPDUI
  record PlaybackState,
    state : String = "stop",
    song : Song? = nil,
    song_position : Int32? = nil,
    playlist_version : String? = nil,
    elapsed : Float64 = 0.0,
    duration : Float64 = 0.0,
    random : Bool = false,
    repeat : Bool = false,
    volume : Int32? = nil do
    def playing? : Bool
      state == "play"
    end

    def paused? : Bool
      state == "pause"
    end

    def stopped? : Bool
      state == "stop"
    end

    def with_elapsed(value : Float64) : self
      PlaybackState.new(state, song, song_position, playlist_version, value, duration, random, repeat, volume)
    end

    def with_random(value : Bool) : self
      PlaybackState.new(state, song, song_position, playlist_version, elapsed, duration, value, repeat, volume)
    end

    def with_repeat(value : Bool) : self
      PlaybackState.new(state, song, song_position, playlist_version, elapsed, duration, random, value, volume)
    end

    def with_volume(value : Int32?) : self
      PlaybackState.new(state, song, song_position, playlist_version, elapsed, duration, random, repeat, value)
    end
  end
end
