module MPDUI
  module AppPlayer
    private def bind_event_bridge : Nil
      @event_bridge.refresh_requested.connect do
        refresh_status
      end

      @event_bridge.progress_requested.connect do |elapsed|
        @elapsed = elapsed
        update_progress
      end

      @event_bridge.random_changed.connect do |enabled|
        @random = enabled
        sync_toggle_buttons
      end

      @event_bridge.repeat_changed.connect do |enabled|
        @repeat = enabled
        sync_toggle_buttons
      end

      @event_bridge.volume_changed.connect do |volume|
        update_volume_control(volume)
      end
    end

    private def toggle_play_pause : Nil
      mpd_action do |client|
        status = client.status
        if status && status["state"]? == "play"
          client.pause(true)
        else
          client.play
        end
      end
    end

    private def refresh_status : Nil
      client = @client
      return unless client

      status = client.status
      unless status
        Log.info { "mpd_ui: waiting for MPD status after reconnect to #{@settings.host}:#{@settings.port}" }
        set_status("Reconnecting to #{@settings.host}:#{@settings.port}…")
        update_tray_tooltip("Reconnecting", "#{@settings.host}:#{@settings.port}")
        return
      end

      song = client.currentsong

      state = status.fetch("state", "stop")
      previous_song_pos = @current_song_pos
      @state = state
      @current_song_pos = status["song"]?.try(&.to_i?)
      @elapsed = status["elapsed"]?.try(&.to_f?) || @elapsed
      @duration = status["duration"]?.try(&.to_f?) || @duration
      @random = status["random"]? == "1"
      @repeat = status["repeat"]? == "1"
      @volume = status["volume"]?.try(&.to_i?)

      if button = @play_pause_button
        if icon = (state == "play" ? @pause_icon : @play_icon)
          button.icon = icon
        end
      end
      sync_toggle_buttons
      update_volume_control(@volume)
      update_progress
      refresh_playlist(song_changed: previous_song_pos != @current_song_pos)

      if song
        file = song["file"]?
        title = song["Title"]? || (file ? File.basename(file, File.extname(file)) : "Unknown")
        artist = song["Artist"]?
        album = song["Album"]?
        subtitle = [artist, album].compact.join(" • ")

        @title_label.try(&.text = title)
        @subtitle_label.try(&.text = subtitle.empty? ? " " : subtitle)
        set_status("State: #{state.capitalize} • #{@settings.host}:#{@settings.port}")
        @window.try(&.window_title = artist ? "#{artist} — #{title}" : title)
        update_tray_tooltip(title, subtitle)

        if file && file != @current_file
          @current_file = file
          load_cover_art(file)
        elsif !file
          clear_cover_art
        end
      elsif state == "stop"
        @current_file = ""
        clear_cover_art
        @title_label.try(&.text = "Stopped")
        @subtitle_label.try(&.text = "")
        set_status("Connected to #{@settings.host}:#{@settings.port}")
        @window.try(&.window_title = App::WINDOW_TITLE)
        update_tray_tooltip("Stopped", "#{@settings.host}:#{@settings.port}")
      else
        set_status("State: #{state.capitalize} • #{@settings.host}:#{@settings.port}")
        update_tray_tooltip("State: #{state.capitalize}", "#{@settings.host}:#{@settings.port}")
      end
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      set_status("MPD request failed")
      update_tray_tooltip("Error", ex.message || ex.to_s)
    end

    private def update_progress : Nil
      slider = @progress_slider
      return unless slider
      return if @dragging_progress

      @syncing_progress = true
      pct = @duration > 0 ? ((@elapsed / @duration) * 1000.0).clamp(0.0, 1000.0).round.to_i : 0
      slider.value = pct
      @time_label.try(&.text = "#{format_time(@elapsed)} / #{format_time(@duration)}")
      @syncing_progress = false
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

    private def load_cover_art(uri : String) : Nil
      client = @client
      return clear_cover_art unless client

      response = begin
        client.readpicture(uri)
      rescue
        nil
      end
      response ||= begin
        client.albumart(uri)
      rescue
        nil
      end

      if response
        _meta, io = response
        io.rewind
        pixmap = Qt6::QPixmap.from_data(io.to_slice)

        if pixmap.null?
          clear_cover_art
        else
          scaled = pixmap.scaled(
            160,
            160,
            Qt6::AspectRatioMode::Keep,
            Qt6::TransformationMode::Smooth
          )
          @cover_label.try(&.text = "")
          @cover_label.try(&.pixmap = scaled)
        end
      else
        clear_cover_art
      end
    rescue
      clear_cover_art
    end

    private def clear_cover_art : Nil
      @cover_label.try(&.pixmap = nil)
      @cover_label.try(&.text = "No Cover")
    end

    private def sync_toggle_buttons : Nil
      @syncing = true
      @shuffle_button.try(&.checked = @random)
      @repeat_button.try(&.checked = @repeat)
      @syncing = false
    end
  end
end
