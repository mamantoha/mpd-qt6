module MPDUI
  class App
    WINDOW_TITLE = "Crystal MPD"

    @settings : Settings
    @qt_app : Qt6::Application
    @window : Qt6::MainWindow?
    @cover_label : Qt6::Label?
    @title_label : Qt6::Label?
    @subtitle_label : Qt6::Label?
    @status_bar : Qt6::StatusBar?
    @time_label : Qt6::Label?
    @play_pause_button : Qt6::PushButton?
    @shuffle_button : Qt6::PushButton?
    @repeat_button : Qt6::PushButton?
    @progress_slider : Qt6::Slider?
    @playlist_table : Qt6::TableWidget?
    @delete_queue_action : Qt6::Action?
    @database_tree : Qt6::TreeView?
    @database_model : Qt6::StandardItemModel?
    @database_loaded : Bool = false
    @database_loading : Bool = false
    @database_drag_filter : Qt6::EventFilter?
    @queue_drop_filter : Qt6::EventFilter?
    @playlist_drag_source_row : Int32? = nil
    @dragged_database_uris : Array(String) = [] of String
    # Track drag source: :playlist, :database, or nil
    @drag_source_type : Symbol? = nil
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
    @just_moved_pos : Int32? = nil
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
      window = Qt6::MainWindow.new
      window.window_title = WINDOW_TITLE
      window.resize(700, 720)
      build_menu(window)
      status_bar = window.status_bar
      status_bar.show_message("Ready")

      central = Qt6::Widget.new(window)
      central.vbox do |column|
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

        progress = Qt6::Widget.new(central)
        progress.hbox do |row|
          progress_slider = Qt6::Slider.new(Qt6::Orientation::Horizontal)
          progress_slider.set_range(0, 1000)
          progress_slider.value = 0
          progress_slider.minimum_width = 320
          progress_slider.click_to_position = true

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

        controls = Qt6::Widget.new(central)
        controls.hbox do |row|
          prev_button = Qt6::PushButton.new("")
          play_pause_button = Qt6::PushButton.new("")
          next_button = Qt6::PushButton.new("")
          shuffle_button = Qt6::PushButton.new("")
          repeat_button = Qt6::PushButton.new("")
          clear_button = Qt6::PushButton.new("")

          play_icon = Qt6::QIcon.from_theme("media-playback-start")
          pause_icon = Qt6::QIcon.from_theme("media-playback-pause")
          stop_icon = Qt6::QIcon.from_theme("media-playback-stop")
          prev_icon = Qt6::QIcon.from_theme("media-skip-backward")
          next_icon = Qt6::QIcon.from_theme("media-skip-forward")
          shuffle_icon = Qt6::QIcon.from_theme("media-playlist-shuffle")
          repeat_icon = Qt6::QIcon.from_theme("media-playlist-repeat")
          clear_icon = Qt6::QIcon.from_theme("edit-clear")

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
          clear_button.icon = clear_icon unless clear_icon.null?
          prev_button.icon_size = Qt6::Size.new(22, 22)
          play_pause_button.icon_size = Qt6::Size.new(22, 22)
          next_button.icon_size = Qt6::Size.new(22, 22)
          shuffle_button.icon_size = Qt6::Size.new(22, 22)
          repeat_button.icon_size = Qt6::Size.new(22, 22)
          clear_button.icon_size = Qt6::Size.new(22, 22)
          shuffle_button.style_sheet = toggle_button_style
          repeat_button.style_sheet = toggle_button_style
          prev_button.fixed_width = 44
          play_pause_button.fixed_width = 44
          next_button.fixed_width = 44
          shuffle_button.fixed_width = 44
          repeat_button.fixed_width = 44
          clear_button.fixed_width = 44
          prev_button.tool_tip = "Previous"
          play_pause_button.tool_tip = "Play/Pause"
          next_button.tool_tip = "Next"
          shuffle_button.tool_tip = "Shuffle"
          repeat_button.tool_tip = "Repeat"
          clear_button.tool_tip = "Clear Queue"

          shuffle_button.checkable = true
          repeat_button.checkable = true

          prev_button.on_clicked { mpd_action { |c| c.previous } }
          play_pause_button.on_clicked { toggle_play_pause }
          next_button.on_clicked { mpd_action { |c| c.next } }
          clear_button.on_clicked { clear_queue }
          shuffle_button.on_toggled { |checked| mpd_action { |c| c.random(checked) } unless @syncing }
          repeat_button.on_toggled { |checked| mpd_action { |c| c.repeat(checked) } unless @syncing }

          row.add_stretch
          row << prev_button
          row << play_pause_button
          row << next_button
          row << shuffle_button
          row << repeat_button
          row << clear_button
          row.add_stretch

          @play_pause_button = play_pause_button
          @shuffle_button = shuffle_button
          @repeat_button = repeat_button
          @play_icon = play_icon
          @pause_icon = pause_icon
          @stop_icon = stop_icon
        end

        playlist_table = build_playlist(central)
        setup_queue_drop_target(playlist_table)
        database_browser = build_database_browser(central)

        browsers = Qt6::Splitter.new(Qt6::Orientation::Horizontal, central)

        database_panel = Qt6::Widget.new(central)
        database_panel.minimum_width = 220
        database_panel.vbox do |database_column|
          database_column << Qt6::Label.new("Database")
          database_column << database_browser
        end

        queue_panel = Qt6::Widget.new(central)
        queue_panel.minimum_width = 220
        queue_panel.tool_tip = "Drop songs, albums, or artists here to insert them into the queue"
        queue_panel.vbox do |queue_column|
          queue_column << Qt6::Label.new("Queue")
          queue_column << playlist_table
        end

        browsers << database_panel
        browsers << queue_panel

        ensure_database_loaded

        column << cover_label
        column << title_label
        column << subtitle_label
        column << progress
        column << controls
        column << browsers

        @cover_label = cover_label
        @title_label = title_label
        @subtitle_label = subtitle_label
        @playlist_table = playlist_table
      end

      window.central_widget = central
      @window = window
      @status_bar = status_bar
    end

    private def build_menu(window : Qt6::MainWindow) : Nil
      menu_bar = window.menu_bar

      app_menu = menu_bar.add_menu("&App")
      about_action = Qt6::Action.new("About", window)
      about_action.status_tip = "Show application and MPD server information"
      about_action.on_triggered { open_about_dialog }
      app_menu.add_action(about_action)
      app_menu.add_separator

      settings_action = Qt6::Action.new("Settings", window)
      settings_action.shortcut = "Ctrl+,"
      settings_action.status_tip = "Open connection settings"
      settings_action.on_triggered { open_settings_dialog }
      app_menu.add_action(settings_action)
      app_menu.add_separator

      quit_action = Qt6::Action.new("Quit", window)
      quit_action.shortcut = "Ctrl+Q"
      quit_action.status_tip = "Quit the application"
      quit_action.on_triggered { @qt_app.quit }
      app_menu.add_action(quit_action)

      library_menu = menu_bar.add_menu("&Library")
      reload_action = Qt6::Action.new("Reload Database", window)
      reload_action.shortcut = "F5"
      reload_action.status_tip = "Reload the music database from MPD"
      reload_action.on_triggered { ensure_database_loaded(force: true) }
      library_menu.add_action(reload_action)

      queue_menu = menu_bar.add_menu("&Queue")
      clear_action = Qt6::Action.new("Clear Queue", window)
      clear_action.shortcut = "Ctrl+L"
      clear_action.status_tip = "Remove all songs from the queue"
      clear_action.on_triggered { clear_queue }
      queue_menu.add_action(clear_action)
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
      table.drag_enabled = true
      table.accept_drops = true
      table.drag_drop_mode = Qt6::ItemViewDragDropMode::DragDrop
      table.drag_drop_overwrite_mode = false
      table.default_drop_action = Qt6::DropAction::MoveAction
      table.drop_indicator_shown = true
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

      delete_action = Qt6::Action.new("Remove from Queue", table)
      delete_action.shortcut = "Delete"
      delete_action.on_triggered do
        next unless table.has_focus? || table.viewport.has_focus?
        delete_selected_playlist_row
      end
      table.add_action(delete_action)
      @delete_queue_action = delete_action

      # table.on_current_cell_changed do
      #   row = table.current_row
      # end

      table
    end

    private def build_database_browser(parent : Qt6::Widget) : Qt6::Widget
      container = Qt6::Widget.new(parent)
      tree = Qt6::TreeView.new(container)
      model = Qt6::StandardItemModel.new(tree)

      model.set_horizontal_header_label(0, "Database")
      tree.model = model
      tree.header_hidden = true
      tree.root_is_decorated = true
      tree.uniform_row_heights = true
      tree.selection_mode = Qt6::ItemSelectionMode::SingleSelection
      tree.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      tree.alternating_row_colors = true
      tree.drag_enabled = true
      tree.drag_drop_mode = Qt6::ItemViewDragDropMode::DragOnly
      tree.default_drop_action = Qt6::DropAction::CopyAction
      tree.drop_indicator_shown = true
      tree.minimum_height = 320

      tree.style_sheet = <<-CSS
        QTreeView {
          border: 1px solid;
        }
        QTreeView::item {
          padding: 4px 6px;
        }
      CSS

      tree.on_current_index_changed do
        @playlist_drag_source_row = nil
        @dragged_database_uris = selected_database_uris
      end

      container.vbox do |column|
        column << tree
      end

      @database_tree = tree
      @database_model = model
      setup_database_drag_source(tree)
      show_database_message("Open the Database tab to load your library")
      container
    end

    private def setup_database_drag_source(tree : Qt6::TreeView) : Nil
      viewport = tree.viewport
      filter = Qt6::EventFilter.new(viewport)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          @playlist_drag_source_row = nil
          @drag_source_type = :database
        when Qt6::EventType::DragEnter
          @drag_source_type = :database
        when Qt6::EventType::DragLeave, Qt6::EventType::Drop
          @drag_source_type = nil
        end
        false
      end

      viewport.install_event_filter(filter)
      @database_drag_filter = filter
    end

    private def setup_queue_drop_target(table : Qt6::TableWidget) : Nil
      viewport = table.viewport
      viewport.accept_drops = true

      filter = Qt6::EventFilter.new(viewport)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          row = table.current_row
          @playlist_drag_source_row = row >= 0 ? row : nil
          @dragged_database_uris.clear
          @drag_source_type = :playlist
          false
        when Qt6::EventType::DragEnter
          # Determine drag source if not already set (external drags)
          @drag_source_type ||= :playlist
          false
        when Qt6::EventType::DragMove
          row = table.current_row
          @playlist_drag_source_row = row >= 0 ? row : nil

          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          # Accept if either operation is available
          if drag_is_playlist_reorder?(drop_event)
            drop_event.accept_proposed_action
          elsif drag_is_database_drop?(drop_event)
            @dragged_database_uris = selected_database_uris if selected_database_uris.any?
            drop_event.accept_proposed_action
          end
          false
        when Qt6::EventType::DragLeave
          @playlist_drag_source_row = nil
          @drag_source_type = nil
          false
        when Qt6::EventType::Drop
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          handled = false
          if @drag_source_type == :playlist && drag_is_playlist_reorder?(drop_event)
            handled = move_playlist_row(@playlist_drag_source_row.not_nil!, queue_drop_row_for(drop_event))
          elsif @drag_source_type == :database && drag_is_database_drop?(drop_event)
            handled = append_selected_database_to_queue(queue_drop_row_for(drop_event))
          end

          if handled
            drop_event.accept_proposed_action
          else
            drop_event.ignore
          end

          @playlist_drag_source_row = nil
          @drag_source_type = nil
          true
        else
          false
        end
      end

      viewport.install_event_filter(filter)
      @queue_drop_filter = filter
    end

    # Helper: is this drag a playlist reorder?
    private def drag_is_playlist_reorder?(event : Qt6::DropEvent) : Bool
      table = @playlist_table
      row = @playlist_drag_source_row
      @drag_source_type == :playlist && !!event.mime_data && !!table && !row.nil? && table.row_count > 1
    end

    # Helper: is this drag a database drop?
    private def drag_is_database_drop?(event : Qt6::DropEvent) : Bool
      @drag_source_type == :database && !!event.mime_data && (@dragged_database_uris.any? || selected_database_uris.any?)
    end

    private def queue_drop_row_for(event : Qt6::DropEvent) : Int32
      table = @playlist_table
      return 0 unless table
      return 0 if table.row_count <= 0

      y = event.position.y
      return 0 if y <= 4.0

      index = table.index_at(event.position)
      unless index.valid?
        index.release
        return table.row_count
      end

      rect = table.visual_rect(index)
      row = index.row
      index.release

      y < rect.y + rect.height / 2.0 ? row : row + 1
    end

    private def move_playlist_row(source_row : Int32, insert_row : Int32) : Bool
      source_pos = @playlist_positions[source_row]?
      return false unless source_pos

      target_row = insert_row.clamp(0, @playlist_positions.size)
      target_row -= 1 if target_row > source_row
      return true if target_row == source_row

      mpd_action do |client|
        client.move(source_pos, target_row)
      end

      @just_moved_pos = target_row
      set_status("Queue order updated")
      true
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      false
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
      set_status("Unable to connect to #{@settings.host}:#{@settings.port}")
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

    private def open_about_dialog : Nil
      parent = @window
      return unless parent

      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = "About #{WINDOW_TITLE}"
      dialog.resize(520, 420)

      title_label = Qt6::Label.new("#{WINDOW_TITLE} #{VERSION}", dialog)
      title_label.style_sheet = "font-size: 18px; font-weight: bold;"

      description_label = Qt6::Label.new("A Qt 6 desktop client for Music Player Daemon with queue management, database browsing, and playback controls.", dialog)
      description_label.word_wrap = true

      stats_label = Qt6::Label.new("MPD Server", dialog)
      stats_label.style_sheet = "font-weight: bold;"

      stats_view = Qt6::PlainTextEdit.new(about_server_details, dialog)
      stats_view.read_only = true
      stats_view.minimum_height = 220

      button_box = Qt6::DialogButtonBox.new(Qt6::DialogButtonBoxStandardButton::Ok, dialog)
      button_box.on_accepted { dialog.accept }

      dialog.vbox do |column|
        column << title_label
        column << description_label
        column << stats_label
        column << stats_view
        column << button_box
      end

      dialog.exec
    ensure
      dialog.try(&.release)
    end

    private def clear_queue : Nil
      mpd_action do |client|
        client.clear
      end
      set_status("Queue cleared")
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
        set_status("Reconnecting to #{@settings.host}:#{@settings.port}…")
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

      if button = @play_pause_button
        if icon = (state == "play" ? @pause_icon : @play_icon)
          button.icon = icon
        end
      end
      sync_toggle_buttons
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
        @window.try(&.window_title = WINDOW_TITLE)
      else
        set_status("State: #{state.capitalize} • #{@settings.host}:#{@settings.port}")
      end
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      set_status("MPD request failed")
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

    private def refresh_playlist(*, song_changed : Bool = false) : Nil
      client = @client
      table = @playlist_table
      return unless client && table

      songs = client.playlistinfo
      return unless songs

      flags = Qt6::ItemFlag::Selectable | Qt6::ItemFlag::Enabled | Qt6::ItemFlag::DragEnabled

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

      if @just_moved_pos && (row = @playlist_positions.index(@just_moved_pos))
        table.set_current_cell(row, 1)
        @just_moved_pos = nil
      elsif song_changed
        scroll_playlist_to_current_song
      end
    ensure
      @syncing = false
    end

    private def scroll_playlist_to_current_song : Nil
      table = @playlist_table
      current_song_pos = @current_song_pos
      return unless table && current_song_pos

      row = @playlist_positions.index(current_song_pos)
      return unless row

      table.set_current_cell(row, 1)
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

    private def delete_selected_playlist_row : Nil
      return if @syncing

      table = @playlist_table
      return unless table

      row = table.current_row
      return if row < 0

      pos = @playlist_positions[row]?
      return unless pos

      mpd_action { |c| c.delete(pos) }
      set_status("Removed song from Queue")
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
      set_status("Loading database from #{@settings.host}:#{@settings.port}…")

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
            set_status("Database loaded • #{songs.size} songs")
          end
        rescue ex
          @qt_app.invoke_later do
            @database_loaded = false
            @database_loading = false
            show_database_message("Failed to load database")
            set_status("Database load failed: #{ex.message || ex}")
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

    private def selected_database_uris : Array(String)
      tree = @database_tree
      model = @database_model
      return [] of String unless tree && model

      index = tree.current_index
      return [] of String unless index.valid?

      item = model.item_from_index(index)
      return [] of String unless item

      uris = [] of String
      collect_database_uris(item, uris)
      uris.uniq!
      uris
    end

    private def collect_database_uris(item : Qt6::StandardItem, uris : Array(String)) : Nil
      case data = item.data(Qt6::ItemDataRole::User)
      when String
        uris << data unless data.empty?
      end

      item.row_count.times do |row|
        child = item.child(row)
        collect_database_uris(child, uris) if child
      end
    end

    private def append_selected_database_to_queue(insert_row : Int32? = nil) : Bool
      uris = @dragged_database_uris.empty? ? selected_database_uris : @dragged_database_uris.dup
      return false if uris.empty?

      mpd_action do |client|
        client.with_command_list do
          if insert_row && insert_row < @playlist_positions.size
            base_position = @playlist_positions[insert_row]? || insert_row
            uris.each_with_index do |uri, offset|
              client.addid(uri, base_position + offset)
            end
          else
            uris.each { |uri| client.add(uri) }
          end
        end
      end
      suffix = uris.size == 1 ? "song" : "songs"
      action = insert_row ? "Inserted" : "Added"
      set_status("#{action} #{uris.size} #{suffix} from Database")
      @dragged_database_uris.clear
      true
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      false
    end

    private def set_status(message : String) : Nil
      @status_bar.try(&.show_message(message))
    end

    private def about_server_details : String
      client = @client

      lines = [
        "Host: #{@settings.host}",
        "Port: #{@settings.port}",
      ]

      if client
        lines << "MPD Version: #{client.version || "Unknown"}"

        if stats = client.stats
          lines << ""
          lines << "Artists: #{stats.fetch("artists", "Unknown")}"
          lines << "Albums: #{stats.fetch("albums", "Unknown")}"
          lines << "Songs: #{stats.fetch("songs", "Unknown")}"
          lines << "Database Playtime: #{format_stats_duration(stats["db_playtime"]?)}"
          lines << "Played Time: #{format_stats_duration(stats["playtime"]?)}"
          lines << "Uptime: #{format_stats_duration(stats["uptime"]?)}"
          lines << "Last Database Update: #{format_stats_timestamp(stats["db_update"]?)}"
        else
          lines << ""
          lines << "Server statistics are unavailable."
        end
      else
        lines << "MPD Version: Unavailable"
        lines << ""
        lines << "Server statistics are unavailable because the client is not connected."
      end

      lines.join('\n')
    rescue ex
      "Host: #{@settings.host}\nPort: #{@settings.port}\nMPD statistics are unavailable.\nError: #{ex.message || ex.to_s}"
    end

    private def format_stats_duration(raw_seconds : String?) : String
      seconds = raw_seconds.try(&.to_i64?) || return "Unknown"
      return "0s" if seconds <= 0

      parts = [] of String
      days = seconds // 86_400
      hours = (seconds % 86_400) // 3_600
      minutes = (seconds % 3_600) // 60
      secs = seconds % 60

      parts << "#{days}d" if days > 0
      parts << "#{hours}h" if hours > 0
      parts << "#{minutes}m" if minutes > 0
      parts << "#{secs}s" if secs > 0 || parts.empty?
      parts.join(' ')
    end

    private def format_stats_timestamp(raw_timestamp : String?) : String
      timestamp = raw_timestamp.try(&.to_i64?) || return "Unknown"
      Time.unix(timestamp).to_local.to_s("%Y-%m-%d %H:%M:%S %Z")
    rescue
      "Unknown"
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
