module MPDUI
  class EventBridge
    getter refresh_requested : Qt6::Signal() = Qt6::Signal().new
    getter progress_requested : Qt6::Signal(Float64) = Qt6::Signal(Float64).new
    getter random_changed : Qt6::Signal(Bool) = Qt6::Signal(Bool).new
    getter repeat_changed : Qt6::Signal(Bool) = Qt6::Signal(Bool).new

    @refresh_pending : Atomic(Bool) = Atomic(Bool).new(false)
    @progress_pending : Atomic(Bool) = Atomic(Bool).new(false)
    @elapsed_millis : Atomic(Int64) = Atomic(Int64).new(0_i64)

    def initialize(@app : Qt6::Application)
    end

    def reset : Nil
      @refresh_pending.set(false)
      @progress_pending.set(false)
    end

    def request_refresh : Nil
      return if @refresh_pending.swap(true)

      @app.invoke_later do
        @refresh_pending.set(false)
        @refresh_requested.emit
      end
    end

    def request_progress(elapsed : Float64) : Nil
      @elapsed_millis.set((elapsed * 1000.0).round.to_i64)
      return if @progress_pending.swap(true)

      @app.invoke_later do
        @progress_pending.set(false)
        @progress_requested.emit(@elapsed_millis.get / 1000.0)
      end
    end

    def update_random(enabled : Bool) : Nil
      @app.invoke_later { @random_changed.emit(enabled) }
    end

    def update_repeat(enabled : Bool) : Nil
      @app.invoke_later { @repeat_changed.emit(enabled) }
    end
  end

  class App
    WINDOW_TITLE = "Crystal MPD"

    @settings : Settings
    @qt_app : Qt6::Application
    @window : Qt6::Widget?
    @cover_label : Qt6::Label?
    @title_label : Qt6::Label?
    @subtitle_label : Qt6::Label?
    @status_label : Qt6::Label?
    @time_label : Qt6::Label?
    @play_pause_button : Qt6::PushButton?
    @shuffle_button : Qt6::PushButton?
    @repeat_button : Qt6::PushButton?
    @progress_slider : Qt6::Slider?
    @client : MPD::Client?
    @callback_client : MPD::Client?
    @event_bridge : EventBridge
    @play_icon : Qt6::QIcon?
    @pause_icon : Qt6::QIcon?
    @state : String = "stop"
    @elapsed : Float64 = 0.0
    @duration : Float64 = 0.0
    @random : Bool = false
    @repeat : Bool = false
    @syncing : Bool = false
    @syncing_progress : Bool = false
    @dragging_progress : Bool = false
    @current_file : String = ""

    def initialize
      @settings = Settings.load
      @qt_app = Qt6.application
      @qt_app.name = WINDOW_TITLE
      @event_bridge = EventBridge.new(@qt_app)
      bind_event_bridge
    end

    def run : Nil
      build_ui
      connect
      @window.try(&.show)
      exit(@qt_app.run)
    end

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
    end

    private def build_ui : Nil
      window = Qt6.window(WINDOW_TITLE, 520, 320) do |widget|
        widget.vbox do |column|
          cover_label = Qt6::Label.new("No Cover")
          cover_label.set_fixed_size(160, 160)
          cover_label.scaled_contents = true
          cover_label.style_sheet = "background: #222; border: 1px solid #444;"

          title_label = Qt6::Label.new("Connecting...")
          title_label.style_sheet = "font-size: 18px; font-weight: bold;"
          title_label.word_wrap = true

          subtitle_label = Qt6::Label.new("")
          subtitle_label.word_wrap = true

          progress = Qt6::Widget.new(widget)
          progress.hbox do |row|
            progress_slider = Qt6::Slider.new(Qt6::Orientation::Horizontal)
            progress_slider.set_range(0, 1000)
            progress_slider.value = 0
            progress_slider.minimum_width = 320

            time_label = Qt6::Label.new("0:00 / 0:00")

            progress_slider.on_pressed do
              @dragging_progress = true
            end

            progress_slider.on_value_changed do |value|
              next if @syncing_progress || @duration <= 0
              @dragging_progress = true
              target = @duration * value / 1000.0
              @elapsed = target
              @time_label.try(&.text = "#{format_time(target)} / #{format_time(@duration)}")
            end

            progress_slider.on_released do
              next if @syncing_progress || @duration <= 0
              @dragging_progress = false
              target = @duration * progress_slider.value / 1000.0
              @elapsed = target
              update_progress
              mpd_action { |c| c.seekcur(target.to_i) }
            end

            row << progress_slider
            row << time_label

            @progress_slider = progress_slider
            @time_label = time_label
          end

          controls = Qt6::Widget.new(widget)
          controls.hbox do |row|
            prev_button = Qt6::PushButton.new("")
            play_pause_button = Qt6::PushButton.new("")
            next_button = Qt6::PushButton.new("")
            shuffle_button = Qt6::PushButton.new("")
            repeat_button = Qt6::PushButton.new("")

            play_icon = Qt6::QIcon.from_theme("media-playback-start")
            pause_icon = Qt6::QIcon.from_theme("media-playback-pause")
            prev_icon = Qt6::QIcon.from_theme("media-skip-backward")
            next_icon = Qt6::QIcon.from_theme("media-skip-forward")
            shuffle_icon = Qt6::QIcon.from_theme("media-playlist-shuffle")
            repeat_icon = Qt6::QIcon.from_theme("media-playlist-repeat")

            toggle_button_style = <<-CSS
              QPushButton {
                padding: 6px;
                border-width: 1px;
              }
              QPushButton:checked {
                border: 2px solid #4ea1ff;
                background-color: rgba(78, 161, 255, 0.18);
              }
            CSS

            prev_button.icon = prev_icon
            play_pause_button.icon = play_icon
            next_button.icon = next_icon
            shuffle_button.icon = shuffle_icon unless shuffle_icon.null?
            repeat_button.icon = repeat_icon unless repeat_icon.null?
            prev_button.icon_size = Qt6::Size.new(22, 22)
            play_pause_button.icon_size = Qt6::Size.new(22, 22)
            next_button.icon_size = Qt6::Size.new(22, 22)
            shuffle_button.icon_size = Qt6::Size.new(22, 22)
            repeat_button.icon_size = Qt6::Size.new(22, 22)
            shuffle_button.style_sheet = toggle_button_style
            repeat_button.style_sheet = toggle_button_style
            prev_button.fixed_width = 44
            play_pause_button.fixed_width = 44
            next_button.fixed_width = 44
            shuffle_button.fixed_width = 44
            repeat_button.fixed_width = 44
            prev_button.tool_tip = "Previous"
            play_pause_button.tool_tip = "Play/Pause"
            next_button.tool_tip = "Next"
            shuffle_button.tool_tip = "Shuffle"
            repeat_button.tool_tip = "Repeat"

            shuffle_button.checkable = true
            repeat_button.checkable = true

            prev_button.on_clicked { mpd_action { |c| c.previous } }
            play_pause_button.on_clicked { toggle_play_pause }
            next_button.on_clicked { mpd_action { |c| c.next } }
            shuffle_button.on_toggled { |checked| mpd_action { |c| c.random(checked) } unless @syncing }
            repeat_button.on_toggled { |checked| mpd_action { |c| c.repeat(checked) } unless @syncing }

            row << prev_button
            row << play_pause_button
            row << next_button
            row << shuffle_button
            row << repeat_button

            @play_pause_button = play_pause_button
            @shuffle_button = shuffle_button
            @repeat_button = repeat_button
            @play_icon = play_icon
            @pause_icon = pause_icon
          end

          status_label = Qt6::Label.new("Ready")
          status_label.word_wrap = true

          column << cover_label
          column << title_label
          column << subtitle_label
          column << progress
          column << controls
          column << status_label

          @cover_label = cover_label
          @title_label = title_label
          @subtitle_label = subtitle_label
          @status_label = status_label
        end
      end

      @window = window
    end

    private def connect : Nil
      @client.try(&.disconnect)
      @callback_client.try(&.disconnect)

      @client = MPD::Client.new(@settings.host, @settings.port)
      @event_bridge.reset
      start_callback_listener
      refresh_status
    rescue ex
      @title_label.try(&.text = "Connection failed")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      @status_label.try(&.text = "Unable to connect to #{@settings.host}:#{@settings.port}")
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

    private def start_callback_listener : Nil
      host = @settings.host
      port = @settings.port

      Thread.new do
        cb = MPD::Client.new(host, port, with_callbacks: true)
        cb.callbacks_timeout = 200.milliseconds

        cb.on_callback do |event, value|
          case event
          when .elapsed?
            if elapsed = value.to_f?
              @event_bridge.request_progress(elapsed)
            end
          when .random?
            @event_bridge.update_random(value == "1")
          when .repeat?
            @event_bridge.update_repeat(value == "1")
          when .song?, .state?, .playlist?, .duration?
            @event_bridge.request_refresh
          end
        end

        @callback_client = cb
        loop { sleep 1.second }
      rescue
        @event_bridge.request_refresh
      end
    end

    private def refresh_status : Nil
      client = @client
      return unless client

      status = client.status
      song = client.currentsong

      state = status.try(&.fetch("state", "stop")) || "stop"
      @state = state
      @elapsed = status.try(&.[]?("elapsed")).try(&.to_f?) || 0.0
      @duration = status.try(&.[]?("duration")).try(&.to_f?) || 0.0
      @random = status.try(&.[]?("random")) == "1"
      @repeat = status.try(&.[]?("repeat")) == "1"

      if button = @play_pause_button
        if icon = (state == "play" ? @pause_icon : @play_icon)
          button.icon = icon
        end
      end
      sync_toggle_buttons
      update_progress

      if song
        file = song["file"]?
        title = song["Title"]? || (file ? File.basename(file, File.extname(file)) : "Unknown")
        artist = song["Artist"]?
        album = song["Album"]?
        subtitle = [artist, album].compact.join(" • ")

        @title_label.try(&.text = title)
        @subtitle_label.try(&.text = subtitle.empty? ? " " : subtitle)
        @status_label.try(&.text = "State: #{state.capitalize} • #{@settings.host}:#{@settings.port}")
        @window.try(&.window_title = artist ? "#{artist} — #{title}" : title)

        if file && file != @current_file
          @current_file = file
          load_cover_art(file)
        elsif !file
          clear_cover_art
        end
      else
        @current_file = ""
        clear_cover_art
        @title_label.try(&.text = state == "stop" ? "Stopped" : "No track")
        @subtitle_label.try(&.text = "")
        @status_label.try(&.text = "Connected to #{@settings.host}:#{@settings.port}")
        @window.try(&.window_title = WINDOW_TITLE)
      end
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      @status_label.try(&.text = "MPD request failed")
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
          @cover_label.try(&.text = "")
          @cover_label.try(&.pixmap = pixmap)
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

    private def format_time(seconds : Float64) : String
      t = seconds.to_i
      "#{t // 60}:#{(t % 60).to_s.rjust(2, '0')}"
    end

    private def sync_toggle_buttons : Nil
      @syncing = true
      @shuffle_button.try(&.checked = @random)
      @repeat_button.try(&.checked = @repeat)
      @syncing = false
    end

    private def mpd_action(& : MPD::Client -> Nil) : Nil
      client = @client
      return unless client
      yield client
      refresh_status
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
    end
  end
end
