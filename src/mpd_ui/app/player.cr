module MPDUI
  module AppPlayer
    private record StatusRefresh,
      status : Hash(String, String)?,
      song : Song?,
      playlist : Array(Song)?,
      error : String?

    private record CoverArtResult,
      result : CoverArtService::Result,
      generation : Int32

    private def bind_event_bridge : Nil
      @event_bridge.refresh_requested.connect do
        request_status_refresh
      end

      @event_bridge.progress_requested.connect do |elapsed|
        @playback_state = @playback_state.with_elapsed(elapsed)
        update_progress
        sync_mpris_position
        sync_lastfm_state(@mpris_song)
      end

      @event_bridge.random_changed.connect do |enabled|
        @playback_state = @playback_state.with_random(enabled)
        sync_toggle_buttons
        sync_mpris_state
      end

      @event_bridge.repeat_changed.connect do |enabled|
        @playback_state = @playback_state.with_repeat(enabled)
        sync_toggle_buttons
        sync_mpris_state
      end

      @event_bridge.volume_changed.connect do |volume|
        @playback_state = @playback_state.with_volume(volume)
        update_volume_control(volume)
        sync_mpris_state
      end
    end

    private def toggle_play_pause : Nil
      mpd_action do |client|
        if @playback_state.playing?
          client.pause(true)
        else
          client.play
        end
      end
    end

    private def refresh_status : Nil
      apply_status_refresh(fetch_status_refresh(@playback_state.playlist_version, @playlist_positions.empty?))
    end

    private def request_status_refresh : Nil
      return if @quitting
      return if @status_refresh_pending.swap(true)

      previous_playlist_version = @playback_state.playlist_version
      playlist_empty = @playlist_positions.empty?

      Thread.new do
        snapshot = fetch_status_refresh(previous_playlist_version, playlist_empty)
        if @quitting
          @status_refresh_pending.set(false)
          next
        end

        @qt_app.invoke_later do
          @status_refresh_pending.set(false)
          next if @quitting

          apply_status_refresh(snapshot)
        end
      end
    end

    private def fetch_status_refresh(previous_playlist_version : String?, playlist_empty : Bool) : StatusRefresh
      client = @client
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

    private def apply_status_refresh(snapshot : StatusRefresh) : Nil
      if error = snapshot.error
        @title_label.try(&.text = "Error")
        @subtitle_label.try(&.text = error)
        set_status("MPD request failed")
        update_tray_tooltip("Error", error)
        return
      end

      status = snapshot.status
      unless status
        Log.info { "mpd_ui: waiting for MPD status after reconnect to #{@settings.host}:#{@settings.port}" }
        set_status("Reconnecting to #{@settings.host}:#{@settings.port}…")
        update_tray_tooltip("Reconnecting", "#{@settings.host}:#{@settings.port}")
        return
      end

      song = snapshot.song

      previous_playback = @playback_state
      playback = playback_state_from_status(status, song)
      @playback_state = playback
      if playback.stopped? || previous_playback.song_position != playback.song_position
        @dragging_progress = false
      end

      if button = @play_pause_button
        if icon = (playback.playing? ? @pause_icon : @play_icon)
          button.icon = icon
        end
      end
      sync_playback_controls
      sync_toggle_buttons
      update_volume_control(playback.volume)
      update_progress

      playlist_changed = previous_playback.playlist_version != playback.playlist_version || @playlist_positions.empty?
      song_changed = previous_playback.song_position != playback.song_position
      state_changed = previous_playback.state != playback.state
      if playlist_changed
        if playlist = snapshot.playlist
          refresh_playlist(playlist, scroll_to_current: !playback.stopped?)
        end
      elsif song_changed
        sync_playlist_indicators(previous_playback.song_position)
        scroll_playlist_to_current_song unless playback.stopped?
      elsif state_changed
        sync_playlist_indicators(previous_playback.song_position)
      end

      if song
        file = song.file
        title = song.display_title
        artist = song.artist
        subtitle = song.subtitle

        @title_label.try(&.text = title)
        @subtitle_label.try(&.text = subtitle.empty? ? " " : subtitle)
        set_status("State: #{playback.state.capitalize} • #{@settings.host}:#{@settings.port}")
        @window.try(&.window_title = artist ? "#{artist} — #{title}" : title)
        update_tray_tooltip(title, subtitle)

        if file && file != @current_file
          @current_file = file
          request_cover_art(file, song)
        elsif !file
          @cover_art_generation.add(1)
          clear_cover_art
        end
      elsif playback.stopped?
        @current_file = ""
        @cover_art_generation.add(1)
        clear_cover_art
        @title_label.try(&.text = "Stopped")
        @subtitle_label.try(&.text = "")
        set_status("Connected to #{@settings.host}:#{@settings.port}")
        @window.try(&.window_title = App::WINDOW_TITLE)
        update_tray_tooltip("Stopped", "#{@settings.host}:#{@settings.port}")
      else
        set_status("State: #{playback.state.capitalize} • #{@settings.host}:#{@settings.port}")
        update_tray_tooltip("State: #{playback.state.capitalize}", "#{@settings.host}:#{@settings.port}")
      end
      sync_mpris_state(song)
      sync_lastfm_state(song)
    end

    private def update_progress : Nil
      slider = @progress_slider
      return unless slider
      return if @dragging_progress

      @syncing_progress = true
      playback = @playback_state
      pct = playback.duration > 0 ? ((playback.elapsed / playback.duration) * 1000.0).clamp(0.0, 1000.0).round.to_i : 0
      slider.value = pct
      @time_label.try(&.text = "#{format_time(playback.elapsed)} / #{format_time(playback.duration)}")
      @syncing_progress = false
    end

    private def sync_playback_controls : Nil
      enabled = !@playback_state.stopped?
      @previous_button.try(&.enabled = enabled)
      @play_pause_button.try(&.enabled = enabled)
      @next_button.try(&.enabled = enabled)
      @progress_slider.try(&.enabled = enabled)
    end

    private def update_volume_control(volume : Int32?) : Nil
      slider = @volume_slider
      return unless slider

      enabled = !!volume && volume >= 0
      @syncing_volume = true
      slider.enabled = enabled
      if enabled
        value = volume.not_nil!.clamp(0, 100)
        slider.value = value
        slider.tool_tip = "#{value}%"
        update_volume_icon(value)
        update_volume_label(value)
      else
        slider.value = 0
        slider.tool_tip = "Volume unavailable"
        update_volume_icon(nil)
        update_volume_label(nil)
      end
      @syncing_volume = false
    end

    private def update_volume_label(volume : Int32?) : Nil
      @volume_label.try(&.text = volume ? "#{volume}%" : "--%")
    end

    private def update_volume_icon(volume : Int32?) : Nil
      button = @volume_button
      return unless button

      icon_name =
        if volume.nil?
          "audio-volume-muted"
        elsif volume <= 0
          "audio-volume-muted"
        elsif volume < 35
          "audio-volume-low"
        elsif volume < 70
          "audio-volume-medium"
        else
          "audio-volume-high"
        end

      icon = Qt6::QIcon.from_theme(icon_name)
      button.icon = icon unless icon.null?
      button.tool_tip = volume ? "#{volume}%" : "Volume unavailable"
    end

    private def playback_state_from_status(status : Hash(String, String), song : Song?) : PlaybackState
      state = status.fetch("state", "stop")
      elapsed =
        if state == "stop"
          0.0
        else
          status["elapsed"]?.try(&.to_f?) || @playback_state.elapsed
        end
      duration =
        if state == "stop"
          0.0
        else
          status["duration"]?.try(&.to_f?) || @playback_state.duration
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

    private def request_cover_art(uri : String, song : Song? = nil) : Nil
      generation = @cover_art_generation.add(1) + 1
      service = CoverArtService.new(@settings.host, @settings.port, Settings::APPLICATION)

      Thread.new do
        result = CoverArtResult.new(service.fetch(uri, song), generation)
        next if @quitting

        @qt_app.invoke_later do
          next if @quitting
          next unless @current_file == result.result.uri
          next unless @cover_art_generation.get == result.generation

          apply_cover_art_result(result)
        end
      end
    end

    private def apply_cover_art_result(result : CoverArtResult) : Nil
      cover = result.result
      if bytes = cover.bytes
        pixmap = Qt6::QPixmap.from_data(bytes)

        if pixmap.null?
          clear_cover_art
        else
          @mpris_art_url = cache_mpris_cover_art(cover.uri, cover.metadata, bytes)
          @cover_label.try(&.tool_tip = cover_art_tooltip(@mpris_art_url, pixmap))
          apply_cover_background(pixmap)
          scaled = pixmap.scaled(
            App::COVER_ART_SIZE,
            App::COVER_ART_SIZE,
            Qt6::AspectRatioMode::Keep,
            Qt6::TransformationMode::Smooth
          )
          @cover_label.try(&.text = "")
          @cover_label.try(&.pixmap = scaled)
        end
      else
        clear_cover_art
      end
    rescue ex
      Log.debug { "cover art: failed to apply cover for #{result.result.uri}: #{ex.message || ex}" }
      clear_cover_art
    end

    private def clear_cover_art : Nil
      @cover_label.try(&.pixmap = nil)
      @cover_label.try(&.text = "No Cover")
      @cover_label.try(&.tool_tip = "")
      @mpris_art_url = ""
      reset_cover_background
    end

    private def cover_art_tooltip(url : String, pixmap : Qt6::QPixmap) : String
      return "" if url.empty? || pixmap.null?

      max_size = 720
      width = pixmap.width
      height = pixmap.height
      if width > max_size || height > max_size
        scale = {max_size.to_f / width, max_size.to_f / height}.min
        width = (width * scale).round.to_i
        height = (height * scale).round.to_i
      end

      %(<img src="#{url}" width="#{width}" height="#{height}">)
    end

    private def apply_cover_background(pixmap : Qt6::QPixmap) : Nil
      return reset_cover_background if pixmap.null?
      return reset_cover_background unless @settings.blurred_cover_background

      width = 960
      height = 260
      scaled = pixmap.scaled(width, height, Qt6::AspectRatioMode::KeepByExpanding, Qt6::TransformationMode::Smooth)
      background = Qt6::QPixmap.new(width, height)
      background.fill(Qt6::Color.new(0, 0, 0, 0))
      Qt6::QPainter.paint(background) do |painter|
        painter.draw_pixmap(Qt6::RectF.new(0, 0, width, height), scaled)
        painter.fill_rect(Qt6::RectF.new(0, 0, width, height), Qt6::Color.new(0, 0, 0, 96))
      end

      @playback_header.try(&.style_sheet = "")
      @playback_header_background.try do |label|
        @playback_header.try do |header|
          size = header.size
          label.resize(size.width, size.height)
          label.move(0, 0)
        end
        label.pixmap = background
        label.visible = true
      end
    end

    private def reset_cover_background : Nil
      @playback_header.try(&.style_sheet = "")
      @playback_header_background.try do |label|
        label.pixmap = nil
        label.visible = false
      end
    end

    private def cache_mpris_cover_art(uri : String, metadata : Hash(String, String), bytes : Bytes) : String
      extension =
        case metadata["type"]?
        when "image/jpeg", "image/jpg"
          ".jpg"
        when "image/png"
          ".png"
        when "image/gif"
          ".gif"
        when "image/webp"
          ".webp"
        else
          ".img"
        end

      cache_prefix = @mpris_service.try(&.options.cache_prefix) || Settings::APPLICATION
      cache_key = "#{uri.hash.to_s(16)}-#{bytes.hash.to_s(16)}"
      path = File.join(Dir.tempdir, "#{cache_prefix}-mpris-cover-#{Process.pid}-#{cache_key}#{extension}")

      if old_path = @mpris_cover_path
        File.delete(old_path) if old_path != path && File.exists?(old_path)
      end

      File.write(path, bytes)
      @mpris_cover_path = path
      "file://#{URI.encode_path(path)}"
    rescue ex
      Log.debug { "mpris: failed to cache cover art for #{uri}: #{ex.message || ex}" }
      ""
    end

    private def sync_toggle_buttons : Nil
      @syncing = true
      @shuffle_button.try(&.checked = @playback_state.random)
      @repeat_button.try(&.checked = @playback_state.repeat)
      @syncing = false
    end
  end
end
