module MPDUI
  module AppMPDConnection
    private def connect : Nil
      Log.info { "mpd_ui: reconnecting to #{@settings.host}:#{@settings.port}" }

      @client.try(&.disconnect)
      @callback_client.try(&.disconnect)
      @stored_playlist_idle_client.try(&.disconnect)
      @callback_client = nil
      @stored_playlist_idle_client = nil

      @client = MPD::Client.new(@settings.host, @settings.port)
      Log.info { "mpd_ui: connected to #{@settings.host}:#{@settings.port}" }
      @library_index.replace([] of Song)
      @database_loaded = false
      @database_loading = false
      show_database_message("Open the Database tab to load your library")
      @event_bridge.reset
      generation = @callback_generation.get + 1
      @callback_generation.set(generation)
      start_callback_listener(generation)
      start_idle_listener(generation)
      refresh_status
      refresh_outputs_menu
      ensure_database_loaded(force: true) if @library_view
      refresh_stored_playlists if @playlists_view
    rescue ex
      Log.error { "mpd_ui: failed to connect to #{@settings.host}:#{@settings.port}: #{ex.message || ex}" }
      @title_label.try(&.text = "Connection failed")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      set_status("Unable to connect to #{@settings.host}:#{@settings.port}")
    end

    private def start_callback_listener(generation : Int32) : Nil
      host = @settings.host
      port = @settings.port

      BackgroundRunner.run("mpd-ui-callbacks") do
        Log.debug { "mpd_ui: starting MPD callback listener for #{host}:#{port}" }
        cb = MPD::Client.new(host, port, with_callbacks: true)
        cb.callbacks_timeout = 200.milliseconds

        cb.on_callback do |event, value|
          next unless @callback_generation.get == generation

          case event
          when .elapsed?
            if elapsed = value.to_f?
              @event_bridge.request_progress(elapsed)
            end
          when .random?
            @event_bridge.update_random(value == "1")
          when .repeat?
            @event_bridge.update_repeat(value == "1")
          when .volume?
            if volume = value.to_i?
              @event_bridge.update_volume(volume)
            end
          when .song?, .state?, .playlist?, .duration?
            @event_bridge.request_refresh
          end
        end

        @callback_client = cb if @callback_generation.get == generation

        loop do
          break unless @callback_generation.get == generation
          sleep 1.second
        end

        cb.disconnect
        Log.debug { "mpd_ui: stopped MPD callback listener for #{host}:#{port}" }
      rescue ex
        Log.warn { "mpd_ui: MPD callback listener failed: #{ex.message || ex}" }
        @event_bridge.request_refresh if @callback_generation.get == generation
      end
    end

    private def start_idle_listener(generation : Int32) : Nil
      host = @settings.host
      port = @settings.port

      BackgroundRunner.run("mpd-ui-idle") do
        Log.debug { "mpd_ui: starting MPD idle listener for #{host}:#{port}" }
        idle_client = MPD::Client.new(host, port)
        @stored_playlist_idle_client = idle_client if @callback_generation.get == generation

        idle_client.on_idle(["stored_playlist", "output"]) do |events|
          next unless @callback_generation.get == generation

          @event_bridge.request_stored_playlists_refresh if events.includes?("stored_playlist")
          @event_bridge.request_outputs_refresh if events.includes?("output")
        end

        loop do
          break unless @callback_generation.get == generation
          sleep 1.second
        end

        idle_client.disconnect
        Log.debug { "mpd_ui: stopped MPD idle listener for #{host}:#{port}" }
      rescue ex
        Log.warn { "mpd_ui: MPD idle listener failed: #{ex.message || ex}" }
        if @callback_generation.get == generation
          @event_bridge.request_stored_playlists_refresh
          @event_bridge.request_outputs_refresh
        end
      end
    end

    private def mpd_action(& : MPD::Client -> Nil) : Nil
      client = @client
      return unless client
      yield client
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
    end
  end
end
