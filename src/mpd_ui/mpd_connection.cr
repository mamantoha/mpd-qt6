module MPDUI
  module AppMPDConnection
    private def connect : Nil
      host = @settings.host
      port = @settings.port
      generation = @connection_generation.add(1) + 1

      Log.info { "mpd_ui: reconnecting to #{host}:#{port}" }

      @client.try(&.disconnect)
      @callback_client.try(&.disconnect)
      @stored_playlist_idle_client.try(&.disconnect)
      @callback_generation.set(@callback_generation.get + 1)
      @mpd_available = false
      @callback_client = nil
      @stored_playlist_idle_client = nil
      @library_index.replace([] of Song)
      @database_loaded = false
      @database_loading = false
      @client = nil
      @event_bridge.reset
      wait_for_status_after_reconnect

      run_background(
        ->(client : MPD::Client) {
          if generation != @connection_generation.get
            client.disconnect
          else
            finish_connect(host, port, client)
          end
        },
        ->(ex : Exception) {
          fail_connect(host, port, ex) if generation == @connection_generation.get
        }
      ) do
        MPD::Client.new(host, port)
      end
    end

    private def finish_connect(host : String, port : Int32, client : MPD::Client) : Nil
      @client.try(&.disconnect)
      @client = client
      @waiting_for_mpd_status = false
      Log.info { "mpd_ui: connected to #{host}:#{port}" }
      show_database_message("Open the Database tab to load your library")
      @event_bridge.reset
      callback_generation = @callback_generation.get + 1
      @callback_generation.set(callback_generation)
      @mpd_available = true
      start_callback_listener(callback_generation)
      start_idle_listener(callback_generation)
      refresh_status
      refresh_outputs_menu
      ensure_database_loaded(force: true) if @library_view
      refresh_stored_playlists if @playlists_view
    end

    private def fail_connect(host : String, port : Int32, ex : Exception) : Nil
      Log.error { "mpd_ui: failed to connect to #{host}:#{port}: #{ex.message || ex}" }
      @client = nil
      @mpd_available = false
      @waiting_for_mpd_status = false
      @title_label.try(&.text = "Connection failed")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      set_status("Unable to connect to #{host}:#{port}")
      show_database_message("Unable to connect to #{host}:#{port}")
      @playlists_view.try(&.render_message("Unable to connect to MPD"))
      clear_outputs_menu("Disconnected")
      sync_playback_controls
    end

    private def start_callback_listener(generation : Int32) : Nil
      host = @settings.host
      port = @settings.port

      BackgroundRunner.run("mpd-ui-callbacks") do
        begin
          Log.debug { "mpd_ui: starting MPD callback listener for #{host}:#{port}" }
          cb = MPD::Client.new(host, port, with_callbacks: true, reconnect_policy: MPD::Client::ReconnectPolicy::Forever)
          cb.callbacks_timeout = 200.milliseconds
          cb.reconnect_interval = 1.second
          @callback_client = cb if @callback_generation.get == generation

          cb.on_connection_error do |error|
            next unless @callback_generation.get == generation

            Log.warn { "mpd_ui: MPD callback listener connection error: #{error.message || error}" }
            @event_bridge.request_connection_lost
            @event_bridge.request_refresh
          end

          cb.on_reconnect do
            next unless @callback_generation.get == generation

            Log.info { "mpd_ui: MPD callback listener reconnected to #{host}:#{port}" }
            @event_bridge.request_connection_restored
          end

          cb.on_callback do |event, value|
            next unless @callback_generation.get == generation

            handle_mpd_status_event(event, value)
          end
        rescue ex
          Log.warn { "mpd_ui: MPD callback listener failed: #{ex.message || ex}" }
        end
      end
    end

    private def start_idle_listener(generation : Int32) : Nil
      host = @settings.host
      port = @settings.port

      BackgroundRunner.run("mpd-ui-idle") do
        begin
          Log.debug { "mpd_ui: starting MPD idle listener for #{host}:#{port}" }
          idle_client = MPD::Client.new(host, port, reconnect_policy: MPD::Client::ReconnectPolicy::Forever)
          idle_client.reconnect_interval = 1.second
          @stored_playlist_idle_client = idle_client if @callback_generation.get == generation
          @event_bridge.request_stored_playlists_refresh
          @event_bridge.request_outputs_refresh

          idle_client.on_connection_error do |error|
            next unless @callback_generation.get == generation

            Log.warn { "mpd_ui: MPD idle listener connection error: #{error.message || error}" }
            @event_bridge.request_connection_lost
            @event_bridge.request_refresh
          end

          idle_client.on_reconnect do
            next unless @callback_generation.get == generation

            Log.info { "mpd_ui: MPD idle listener reconnected to #{host}:#{port}" }
            @event_bridge.request_connection_restored
          end

          idle_client.on_idle(["stored_playlist", "output"]) do |events|
            next unless @callback_generation.get == generation

            @event_bridge.request_stored_playlists_refresh if events.includes?("stored_playlist")
            @event_bridge.request_outputs_refresh if events.includes?("output")
          end
        rescue ex
          Log.warn { "mpd_ui: MPD idle listener failed: #{ex.message || ex}" }
        end
      end
    end

    private def handle_mpd_status_event(event : MPD::Client::Event, value : String) : Nil
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

    private def mpd_action(&block : MPD::Client -> Nil) : Nil
      client = @client
      return unless client

      BackgroundRunner.run("mpd-ui-command") do
        begin
          block.call(client)
        rescue ex
          next if @quitting

          message = ex.message || ex.to_s
          Log.warn { "mpd_ui: MPD command failed: #{message}" }
          @qt_app.invoke_later do
            next if @quitting

            @title_label.try(&.text = "Error")
            @subtitle_label.try(&.text = message)
            set_status("MPD command failed")
          end
        end
      end
    end

    private def with_mpd_client(host : String, port : Int32, & : MPD::Client -> T) : T forall T
      client = MPD::Client.new(host, port)
      yield client
    ensure
      client.try(&.disconnect)
    end
  end
end
