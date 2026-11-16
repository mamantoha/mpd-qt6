module MPDUI
  module AppLastFM
    private def lastfm_client : LastFM::Client
      LastfmAdapter.client
    end

    private def setup_lastfm : Nil
      last_status = @lastfm_adapter.try(&.scrobbler.last_scrobble_status)
      @lastfm_adapter.try(&.stop)
      @lastfm_adapter = LastfmAdapter.new(
        Settings::CACHE_PREFIX,
        -> { @settings.lastfm_enabled? },
        -> { @settings.lastfm_session_key }
      )
      @lastfm_adapter.not_nil!.scrobbler.last_scrobble_status = last_status
    end

    private def sync_lastfm_state(song : Song?) : Nil
      @lastfm_adapter.try(&.sync(@playback_state, song))
    end
  end
end
