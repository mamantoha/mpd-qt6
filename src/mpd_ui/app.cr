module MPDUI
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
    @playlist_table : Qt6::TableWidget?
    @database_tree : Qt6::TreeView?
    @database_model : Qt6::StandardItemModel?
    @database_loaded : Bool = false
    @database_loading : Bool = false
    @client : MPD::Client?
    @callback_client : MPD::Client?
    @event_bridge : EventBridge
    @callback_generation : Atomic(Int32) = Atomic(Int32).new(0)
    @play_icon : Qt6::QIcon?
    @pause_icon : Qt6::QIcon?
    @stop_icon : Qt6::QIcon?
    @state : String = "stop"
    @current_song_pos : Int32? = nil
    @playlist_positions : Array(Int32) = [] of Int32
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
      window = Qt6.window(WINDOW_TITLE, 700, 720) do |widget|
        widget.vbox do |column|
          cover_label = Qt6::Label.new("No Cover")
          cover_label.set_fixed_size(160, 160)
          cover_label.scaled_contents = false
          cover_label.alignment = Qt6::AlignmentFlag::Center
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
            settings_button = Qt6::PushButton.new("")

            play_icon = Qt6::QIcon.from_theme("media-playback-start")
            pause_icon = Qt6::QIcon.from_theme("media-playback-pause")
            stop_icon = Qt6::QIcon.from_theme("media-playback-stop")
            prev_icon = Qt6::QIcon.from_theme("media-skip-backward")
            next_icon = Qt6::QIcon.from_theme("media-skip-forward")
            shuffle_icon = Qt6::QIcon.from_theme("media-playlist-shuffle")
            repeat_icon = Qt6::QIcon.from_theme("media-playlist-repeat")
            settings_icon = Qt6::QIcon.from_theme("preferences-system")

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
            settings_button.icon = settings_icon unless settings_icon.null?
            prev_button.icon_size = Qt6::Size.new(22, 22)
            play_pause_button.icon_size = Qt6::Size.new(22, 22)
            next_button.icon_size = Qt6::Size.new(22, 22)
            shuffle_button.icon_size = Qt6::Size.new(22, 22)
            repeat_button.icon_size = Qt6::Size.new(22, 22)
            settings_button.icon_size = Qt6::Size.new(20, 20)
            shuffle_button.style_sheet = toggle_button_style
            repeat_button.style_sheet = toggle_button_style
            prev_button.fixed_width = 44
            play_pause_button.fixed_width = 44
            next_button.fixed_width = 44
            shuffle_button.fixed_width = 44
            repeat_button.fixed_width = 44
            settings_button.fixed_width = 44
            prev_button.tool_tip = "Previous"
            play_pause_button.tool_tip = "Play/Pause"
            next_button.tool_tip = "Next"
            shuffle_button.tool_tip = "Shuffle"
            repeat_button.tool_tip = "Repeat"
            settings_button.tool_tip = "Connection Settings"

            shuffle_button.checkable = true
            repeat_button.checkable = true

            prev_button.on_clicked { mpd_action { |c| c.previous } }
            play_pause_button.on_clicked { toggle_play_pause }
            next_button.on_clicked { mpd_action { |c| c.next } }
            settings_button.on_clicked { open_settings_dialog }
            shuffle_button.on_toggled { |checked| mpd_action { |c| c.random(checked) } unless @syncing }
            repeat_button.on_toggled { |checked| mpd_action { |c| c.repeat(checked) } unless @syncing }

            row.add_stretch
            row << prev_button
            row << play_pause_button
            row << next_button
            row << shuffle_button
            row << repeat_button
            row << settings_button
            row.add_stretch

            @play_pause_button = play_pause_button
            @shuffle_button = shuffle_button
            @repeat_button = repeat_button
            @play_icon = play_icon
            @pause_icon = pause_icon
            @stop_icon = stop_icon
          end

          playlist_table = build_playlist(widget)
          database_browser = build_database_browser(widget)

          browsers = Qt6::Widget.new(widget)
          browsers.hbox do |row|
            database_panel = Qt6::Widget.new(widget)
            database_panel.vbox do |database_column|
              database_column << Qt6::Label.new("Database")
              database_column << database_browser
            end

            queue_panel = Qt6::Widget.new(widget)
            queue_panel.vbox do |queue_column|
              queue_column << Qt6::Label.new("Queue")
              queue_column << playlist_table
            end

            row << database_panel
            row << queue_panel
          end

          ensure_database_loaded

          status_label = Qt6::Label.new("Ready")
          status_label.word_wrap = true

          column << cover_label
          column << title_label
          column << subtitle_label
          column << progress
          column << controls
          column << status_label
          column << browsers

          @cover_label = cover_label
          @title_label = title_label
          @subtitle_label = subtitle_label
          @status_label = status_label
          @playlist_table = playlist_table
        end
      end

      @window = window
    end

    private def build_playlist(parent : Qt6::Widget) : Qt6::TableWidget
      table = Qt6::TableWidget.new(parent)
      table.column_count = 3
      table.row_count = 0
      table.set_horizontal_header_label(0, "")
      table.set_horizontal_header_label(1, "Track")
      table.set_horizontal_header_label(2, "Time")
      table.selection_mode = Qt6::ItemSelectionMode::SingleSelection
      table.selection_behavior = Qt6::ItemSelectionBehavior::SelectRows
      table.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      table.show_grid = false
      table.minimum_height = 320
      table.style_sheet = <<-CSS
        QTableWidget {
          border: 1px solid;
        }
        QTableWidget::item {
          padding: 4px 6px;
          border: none;
        }
        QTableWidget::item:selected {
          background-color: #4ea1ff;
          color: white;
        }
      CSS

      table.horizontal_header.fixed_height = 0
      table.horizontal_header.set_section_resize_mode(0, Qt6::HeaderResizeMode::ResizeToContents)
      table.horizontal_header.set_section_resize_mode(1, Qt6::HeaderResizeMode::Stretch)
      table.horizontal_header.set_section_resize_mode(2, Qt6::HeaderResizeMode::ResizeToContents)
      table.vertical_header.fixed_width = 0

      table.on_item_double_clicked do |_item|
        play_selected_playlist_row
      end

      table
    end

    private def build_database_browser(parent : Qt6::Widget) : Qt6::Widget
      container = Qt6::Widget.new(parent)
      tree = Qt6::TreeView.new(container)
      model = Qt6::StandardItemModel.new(tree)
      reload_button = Qt6::PushButton.new("Reload")
      add_button = Qt6::PushButton.new("Add Song")
      play_button = Qt6::PushButton.new("Play Song")

      model.set_horizontal_header_label(0, "Database")
      tree.model = model
      tree.header_hidden = true
      tree.root_is_decorated = true
      tree.uniform_row_heights = true
      tree.selection_mode = Qt6::ItemSelectionMode::SingleSelection
      tree.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      tree.alternating_row_colors = true
      tree.minimum_height = 320

      tree.style_sheet = <<-CSS
        QTreeView {
          border: 1px solid;
        }
        QTreeView::item {
          padding: 4px 6px;
        }
      CSS

      reload_button.on_clicked { ensure_database_loaded(force: true) }
      add_button.on_clicked { add_selected_database_song }
      play_button.on_clicked { play_selected_database_song }
      tree.on_current_index_changed { update_database_selection_status }

      container.vbox do |column|
        toolbar = Qt6::Widget.new(container)
        toolbar.hbox do |row|
          row << reload_button
          row << add_button
          row << play_button
          row.add_stretch
        end

        column << toolbar
        column << tree
      end

      @database_tree = tree
      @database_model = model
      show_database_message("Open the Database tab to load your library")
      container
    end

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

    private def open_settings_dialog : Nil
      parent = @window
      return unless parent

      connect if SettingsDialog.edit(parent, @settings)
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

    private def refresh_status : Nil
      client = @client
      return unless client

      status = client.status
      unless status
        Log.info { "mpd_ui: waiting for MPD status after reconnect to #{@settings.host}:#{@settings.port}" }
        @status_label.try(&.text = "Reconnecting to #{@settings.host}:#{@settings.port}…")
        return
      end

      song = client.currentsong

      state = status.fetch("state", "stop")
      @state = state
      @current_song_pos = status["song"]?.try(&.to_i?)
      @elapsed = status["elapsed"]?.try(&.to_f?) || @elapsed
      @duration = status["duration"]?.try(&.to_f?) || @duration
      @random = status["random"]? == "1"
      @repeat = status["repeat"]? == "1"

      if button = @play_pause_button
        if icon = (state == "play" ? @pause_icon : @play_icon)
          button.icon = icon
        end
      end
      sync_toggle_buttons
      update_progress
      refresh_playlist

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
      elsif state == "stop"
        @current_file = ""
        clear_cover_art
        @title_label.try(&.text = "Stopped")
        @subtitle_label.try(&.text = "")
        @status_label.try(&.text = "Connected to #{@settings.host}:#{@settings.port}")
        @window.try(&.window_title = WINDOW_TITLE)
      else
        @status_label.try(&.text = "State: #{state.capitalize} • #{@settings.host}:#{@settings.port}")
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

    private def refresh_playlist : Nil
      client = @client
      table = @playlist_table
      return unless client && table

      songs = client.playlistinfo
      return unless songs

      flags = Qt6::ItemFlag::Selectable | Qt6::ItemFlag::Enabled

      @syncing = true
      @playlist_positions.clear
      table.clear_contents
      table.row_count = songs.size

      songs.each_with_index do |song, row|
        pos = song["Pos"]?.try(&.to_i?) || row
        @playlist_positions << pos

        indicator_icon = playlist_indicator_icon(pos)
        indicator_item = Qt6::TableWidgetItem.new("")
        indicator_item.flags = flags
        indicator_item.icon = indicator_icon.not_nil! if indicator_icon && !indicator_icon.not_nil!.null?

        title_item = Qt6::TableWidgetItem.new(playlist_title(song))
        title_item.flags = flags

        time_item = Qt6::TableWidgetItem.new(playlist_duration(song))
        time_item.flags = flags

        table.set_item(row, 0, indicator_item)
        table.set_item(row, 1, title_item)
        table.set_item(row, 2, time_item)
      end

      if current_pos = @current_song_pos
        if current_row = @playlist_positions.index(current_pos)
          table.set_current_cell(current_row, 1)
        end
      end
    ensure
      @syncing = false
    end

    private def play_selected_playlist_row : Nil
      return if @syncing

      table = @playlist_table
      return unless table

      row = table.current_row
      return if row < 0

      pos = @playlist_positions[row]?
      return unless pos

      mpd_action { |c| c.play(pos) }
    end

    private def playlist_indicator_icon(pos : Int32) : Qt6::QIcon?
      return nil unless pos == @current_song_pos

      case @state
      when "play"
        @play_icon
      when "pause"
        @pause_icon
      else
        @stop_icon
      end
    end

    private def playlist_title(song : Hash(String, String)) : String
      file = song["file"]?
      title = song["Title"]? || (file ? File.basename(file, File.extname(file)) : "Unknown")
      artist = song["Artist"]?
      text = [artist, title].compact.join(" — ")
      text.empty? ? title : text
    end

    private def playlist_duration(song : Hash(String, String)) : String
      if seconds = song["Time"]?.try(&.to_i?)
        format_time(seconds.to_f)
      elsif seconds = song["duration"]?.try(&.to_f?)
        format_time(seconds)
      else
        ""
      end
    end

    private def ensure_database_loaded(*, force : Bool = false) : Nil
      return if @database_loading
      return if @database_loaded && !force

      @database_loading = true
      show_database_message("Loading database…")
      @status_label.try(&.text = "Loading database from #{@settings.host}:#{@settings.port}…")

      host = @settings.host
      port = @settings.port

      Thread.new do
        begin
          db_client = MPD::Client.new(host, port)
          raw_entries = db_client.listallinfo
          songs = database_song_entries(raw_entries)
          library = build_database_library(songs)
          db_client.disconnect

          @qt_app.invoke_later do
            populate_database_tree(library)
            @database_loaded = true
            @database_loading = false
            @status_label.try(&.text = "Database loaded • #{songs.size} songs")
          end
        rescue ex
          @qt_app.invoke_later do
            @database_loaded = false
            @database_loading = false
            show_database_message("Failed to load database")
            @status_label.try(&.text = "Database load failed: #{ex.message || ex}")
          end
        end
      end
    end

    private def show_database_message(message : String) : Nil
      model = @database_model
      return unless model

      model.clear
      model.set_horizontal_header_label(0, "Database")
      model << Qt6::StandardItem.new(message)
    end

    private def database_song_entries(entries : MPD::Object | MPD::Objects | Nil) : Array(Hash(String, String))
      return [] of Hash(String, String) unless entries

      case entries
      when Array
        entries.select { |entry| !!entry["file"]? }
      else
        entries["file"]? ? [entries] : [] of Hash(String, String)
      end
    end

    private def build_database_library(songs : Array(Hash(String, String))) : Hash(String, Hash(String, Array(Hash(String, String))))
      library = Hash(String, Hash(String, Array(Hash(String, String)))).new do |artists, artist|
        artists[artist] = Hash(String, Array(Hash(String, String))).new do |albums, album|
          albums[album] = [] of Hash(String, String)
        end
      end

      songs.each do |song|
        artist = display_name(song["Artist"]?, "[Unknown Artist]")
        album = display_name(song["Album"]?, "[Unknown Album]")
        library[artist][album] << song
      end

      library
    end

    private def populate_database_tree(library : Hash(String, Hash(String, Array(Hash(String, String))))) : Nil
      model = @database_model
      return unless model

      model.clear
      model.set_horizontal_header_label(0, "Database")

      if library.empty?
        model << Qt6::StandardItem.new("Database is empty")
        return
      end

      library.keys.sort.each do |artist|
        artist_item = Qt6::StandardItem.new(artist)

        library[artist].keys.sort.each do |album|
          album_songs = library[artist][album]
          album_item = Qt6::StandardItem.new("#{album} (#{album_songs.size})")

          album_songs.sort_by { |song| {track_number(song), database_song_label(song).downcase} }.each do |song|
            song_item = Qt6::StandardItem.new(database_song_label(song))
            if file = song["file"]?
              song_item.set_data(file, Qt6::ItemDataRole::User)
            end
            album_item << song_item
          end

          artist_item << album_item
        end

        model << artist_item
      end
    end

    private def display_name(value : String?, fallback : String) : String
      if value && !value.strip.empty?
        value
      else
        fallback
      end
    end

    private def database_song_label(song : Hash(String, String)) : String
      file = song["file"]?
      title = display_name(song["Title"]?, file ? File.basename(file, File.extname(file)) : "Unknown")
      track = song["Track"]?.try(&.split('/').first)
      duration = playlist_duration(song)

      base = if track && !track.empty?
               "#{track.rjust(2, '0')}. #{title}"
             else
               title
             end

      duration.empty? ? base : "#{base} • #{duration}"
    end

    private def track_number(song : Hash(String, String)) : Int32
      song["Track"]?.try(&.split('/').first).try(&.to_i?) || Int32::MAX
    end

    private def selected_database_song_uri : String?
      tree = @database_tree
      model = @database_model
      return unless tree && model

      index = tree.current_index
      return unless index.valid?

      item = model.item_from_index(index)
      return unless item

      data = item.data(Qt6::ItemDataRole::User)
      case data
      when String
        data.empty? ? nil : data
      else
        nil
      end
    end

    private def add_selected_database_song : Nil
      uri = selected_database_song_uri
      unless uri
        @status_label.try(&.text = "Select a song in the Database tab")
        return
      end

      mpd_action do |c|
        c.add(uri)
      end
      @status_label.try(&.text = "Added song from Database")
    end

    private def play_selected_database_song : Nil
      uri = selected_database_song_uri
      unless uri
        @status_label.try(&.text = "Select a song in the Database tab")
        return
      end

      client = @client
      return unless client

      added = client.addid(uri)
      if added && (songid = added["Id"]?.try(&.to_i?))
        client.playid(songid)
      else
        client.play
      end
      refresh_status
      @status_label.try(&.text = "Playing song from Database")
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
    end

    private def update_database_selection_status : Nil
      uri = selected_database_song_uri
      return unless uri

      @status_label.try(&.text = "Selected: #{File.basename(uri)}")
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
          scaled = pixmap.scaled(160, 160, keep_aspect_ratio: true, smooth: true)
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
