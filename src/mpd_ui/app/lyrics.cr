module MPDUI
  module AppLyrics
    private def handle_library_tab_changed(index : Int32) : Nil
      return unless index == @lyrics_tab_index

      request_lyrics_for_current_song
      sync_lyrics_position
    end

    private def sync_lyrics_for_playback(previous : PlaybackState, current : PlaybackState, song : Song?) : Nil
      if current.stopped? || song.nil?
        @lyrics_service.cancel
        @lyrics_song_key = nil
        @lyrics_view.try(&.show_empty)
        return
      end

      if previous.song.try(&.file) != song.file
        @lyrics_view.try(&.reset_active_line)
        @lyrics_song_key = nil
        request_lyrics_for_current_song if lyrics_tab_visible?
      end

      sync_lyrics_position
    end

    private def sync_lyrics_position : Nil
      return unless lyrics_tab_visible?

      @lyrics_view.try(&.sync_position(@playback_state.elapsed))
    end

    private def request_lyrics_for_current_song : Nil
      return unless lyrics_tab_visible?

      song = @playback_state.song
      return @lyrics_view.try(&.show_empty) unless song

      key = lyrics_song_key(song)
      return if @lyrics_song_key == key

      @lyrics_song_key = key
      @lyrics_view.try(&.show_loading)
      @lyrics_service.request(song) do |update|
        apply_lyrics_update(key, update)
      end
    end

    private def apply_lyrics_update(key : String, update : LyricsService::Update) : Nil
      unless @lyrics_song_key == key
        LyricsService::Log.info do
          "lyrics update ignored: stale key current=#{@lyrics_song_key.inspect} update=#{key.inspect} status=#{update.status}"
        end
        return
      end

      view = @lyrics_view
      return unless view

      LyricsService::Log.info do
        "lyrics update applied: status=#{update.status} result=#{!!update.result}"
      end

      case update.status
      when LyricsService::Status::Loading
        view.show_loading
      when LyricsService::Status::Found
        if result = update.result
          view.render(result)
          sync_lyrics_position
        else
          view.show_not_found
        end
      when LyricsService::Status::NotFound
        view.show_not_found
      when LyricsService::Status::Failed
        view.show_error(update.error || "Failed to load lyrics")
      end
    end

    private def lyrics_tab_visible? : Bool
      tabs = @library_tabs
      index = @lyrics_tab_index
      !!tabs && !!index && tabs.current_index == index
    end

    private def lyrics_song_key(song : Song) : String
      [
        song.file || "",
        song.artist,
        song.display_title,
        song.duration.try(&.to_i).to_s,
      ].join("\0")
    end
  end
end
