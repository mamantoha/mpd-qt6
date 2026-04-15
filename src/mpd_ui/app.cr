module MPDUI
  class App
    WINDOW_TITLE = "Crystal MPD"

    @settings : Settings
    @qt_app : Qt6::Application
    @window : Qt6::Widget?
    @title_label : Qt6::Label?
    @subtitle_label : Qt6::Label?
    @status_label : Qt6::Label?
    @play_pause_button : Qt6::PushButton?
    @shuffle_box : Qt6::CheckBox?
    @repeat_box : Qt6::CheckBox?
    @status_timer : Qt6::QTimer?
    @client : MPD::Client?
    @random : Bool = false
    @repeat : Bool = false
    @syncing : Bool = false

    def initialize
      @settings = Settings.load
      @qt_app = Qt6.application
      @qt_app.name = WINDOW_TITLE
    end

    def run : Nil
      build_ui
      connect
      start_status_timer
      @window.try(&.show)
      exit(@qt_app.run)
    end

    private def build_ui : Nil
      window = Qt6.window(WINDOW_TITLE, 520, 180) do |widget|
        widget.vbox do |column|
          title_label = Qt6::Label.new("Connecting...")
          title_label.style_sheet = "font-size: 18px; font-weight: bold;"
          title_label.word_wrap = true

          subtitle_label = Qt6::Label.new("")
          subtitle_label.word_wrap = true

          controls = Qt6::Widget.new(widget)
          controls.hbox do |row|
            prev_button = Qt6::PushButton.new("Previous")
            play_pause_button = Qt6::PushButton.new("Play")
            next_button = Qt6::PushButton.new("Next")
            shuffle_box = Qt6::CheckBox.new("Shuffle")
            repeat_box = Qt6::CheckBox.new("Repeat")

            prev_button.on_clicked { mpd_action { |c| c.previous } }
            play_pause_button.on_clicked { toggle_play_pause }
            next_button.on_clicked { mpd_action { |c| c.next } }
            shuffle_box.on_toggled { |checked| mpd_action { |c| c.random(checked) } unless @syncing }
            repeat_box.on_toggled { |checked| mpd_action { |c| c.repeat(checked) } unless @syncing }

            row << prev_button
            row << play_pause_button
            row << next_button
            row << shuffle_box
            row << repeat_box

            @play_pause_button = play_pause_button
            @shuffle_box = shuffle_box
            @repeat_box = repeat_box
          end

          status_label = Qt6::Label.new("Ready")
          status_label.word_wrap = true

          column << title_label
          column << subtitle_label
          column << controls
          column << status_label

          @title_label = title_label
          @subtitle_label = subtitle_label
          @status_label = status_label
        end
      end

      @window = window
    end

    private def start_status_timer : Nil
      timer = Qt6::QTimer.new
      timer.on_timeout { refresh_status }
      timer.start(1000)
      @status_timer = timer
    end

    private def connect : Nil
      @client.try(&.disconnect)
      @client = MPD::Client.new(@settings.host, @settings.port)
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

    private def refresh_status : Nil
      client = @client
      return unless client

      status = client.status
      song = client.currentsong

      state = status.try(&.fetch("state", "stop")) || "stop"
      @random = status.try(&.[]?("random")) == "1"
      @repeat = status.try(&.[]?("repeat")) == "1"

      @play_pause_button.try(&.text = state == "play" ? "Pause" : "Play")
      sync_toggle_buttons

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
      else
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

    private def sync_toggle_buttons : Nil
      @syncing = true
      @shuffle_box.try(&.checked = @random)
      @repeat_box.try(&.checked = @repeat)
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
