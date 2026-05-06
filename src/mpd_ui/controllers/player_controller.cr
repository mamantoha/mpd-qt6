module MPDUI
  class PlayerController
    record StatusRefresh,
      status : Hash(String, String)?,
      song : Song?,
      playlist : Array(Song)?,
      error : String?

    record Transition,
      playback : PlaybackState,
      playlist_changed : Bool,
      song_changed : Bool,
      state_changed : Bool

    def initialize(@client : -> MPD::Client?)
    end

    def fetch_status_refresh(previous_playlist_version : String?, playlist_empty : Bool) : StatusRefresh
      client = @client.call
      return StatusRefresh.new(nil, nil, nil, nil) unless client

      status = client.status
      return StatusRefresh.new(nil, nil, nil, nil) unless status

      song = client.currentsong.try { |metadata| Song.from_mpd(metadata) }
      playlist_version = status["playlist"]?
      playlist = if previous_playlist_version != playlist_version || playlist_empty
                   client.playlistinfo.try(&.map { |metadata| Song.from_mpd(metadata) })
                 end

      StatusRefresh.new(status, song, playlist, nil)
    rescue ex
      StatusRefresh.new(nil, nil, nil, ex.message || ex.to_s)
    end

    def playback_state_from_status(status : Hash(String, String), song : Song?, previous : PlaybackState) : PlaybackState
      state = status.fetch("state", "stop")
      elapsed =
        if state == "stop"
          0.0
        else
          status["elapsed"]?.try(&.to_f?) || previous.elapsed
        end
      duration =
        if state == "stop"
          0.0
        else
          status["duration"]?.try(&.to_f?) || previous.duration
        end

      PlaybackState.new(
        state,
        song,
        status["song"]?.try(&.to_i?),
        status["playlist"]?,
        elapsed,
        duration,
        status["random"]? == "1",
        status["repeat"]? == "1",
        status["volume"]?.try(&.to_i?)
      )
    end

    def transition_from_status(status : Hash(String, String), song : Song?, previous : PlaybackState, playlist_empty : Bool) : Transition
      playback = playback_state_from_status(status, song, previous)
      Transition.new(
        playback,
        previous.playlist_version != playback.playlist_version || playlist_empty,
        previous.song_position != playback.song_position,
        previous.state != playback.state
      )
    end
  end
end
