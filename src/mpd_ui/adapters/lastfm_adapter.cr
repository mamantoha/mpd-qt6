module MPDUI
  class LastfmAdapter
    API_KEY       = "c37fa88f3901c25d5cf4dc186962de40"
    SHARED_SECRET = "5dfe8b3c687c1e4da1f1663e0aeb3e19"

    getter scrobbler : LastFM::Scrobbler

    def self.client : LastFM::Client
      LastFM::Client.new(API_KEY, SHARED_SECRET)
    end

    def initialize(cache_name : String, enabled : -> Bool, session_key : -> String)
      @scrobbler = LastFM::Scrobbler.new(
        cache_name,
        enabled,
        session_key,
        self.class.client
      )
    end

    def sync(playback : PlaybackState, song : Song?) : Nil
      @scrobbler.update(song.try(&.metadata), playback.state, playback.elapsed, playback.duration)
    end

    def stop : Nil
      @scrobbler.stop
    end
  end
end
