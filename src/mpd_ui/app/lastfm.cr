module MPDUI
  module AppLastFM
    LASTFM_API_KEY       = "c37fa88f3901c25d5cf4dc186962de40"
    LASTFM_SHARED_SECRET = "5dfe8b3c687c1e4da1f1663e0aeb3e19"

    private def lastfm_client : LastFM::Client
      LastFM::Client.new(LASTFM_API_KEY, LASTFM_SHARED_SECRET)
    end

    private def setup_lastfm : Nil
      @lastfm_scrobbler = LastFM::Scrobbler.new(
        Settings::APPLICATION,
        -> { @settings.lastfm_enabled },
        -> { @settings.lastfm_session_key },
        lastfm_client
      )
    end

    private def sync_lastfm_state(song : Song?) : Nil
      playback = @playback_state
      @lastfm_scrobbler.try(&.update(song.try(&.metadata), playback.state, playback.elapsed, playback.duration))
    end
  end
end
