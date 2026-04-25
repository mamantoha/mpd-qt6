module MPDUI
  module AppMPDConnection
    private def connect : Nil
      Log.info { "mpd_ui: reconnecting to #{@settings.host}:#{@settings.port}" }

      @client.try(&.disconnect)
      @callback_client.try(&.disconnect)
      @callback_client = nil

      @client = MPD::Client.new(@settings.host, @settings.port)
      Log.info { "mpd_ui: connected to #{@settings.host}:#{@settings.port}" }
      @database_loaded = false
      @database_loading = false
      show_database_message("Open the Database tab to load your library")
      @event_bridge.reset
      generation = @callback_generation.get + 1
      @callback_generation.set(generation)
      start_callback_listener(generation)
      refresh_status
    rescue ex
      Log.error { "mpd_ui: failed to connect to #{@settings.host}:#{@settings.port}: #{ex.message || ex}" }
      @title_label.try(&.text = "Connection failed")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      set_status("Unable to connect to #{@settings.host}:#{@settings.port}")
    end

    private def start_callback_listener(generation : Int32) : Nil
      host = @settings.host
      port = @settings.port

      Thread.new do
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
      rescue
        @event_bridge.request_refresh if @callback_generation.get == generation
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
