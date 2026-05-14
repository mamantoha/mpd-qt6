module MPDUI
  module AppLastFM
    private def lastfm_client : LastFM::Client
      LastfmAdapter.client
    end

    private def setup_lastfm : Nil
      @lastfm_adapter = LastfmAdapter.new(
        Settings::APPLICATION,
        -> { @settings.lastfm_enabled? },
        -> { @settings.lastfm_session_key }
      )
    end

    private def sync_lastfm_state(song : Song?) : Nil
      @lastfm_adapter.try(&.sync(@playback_state, song))
    end
  end
end
