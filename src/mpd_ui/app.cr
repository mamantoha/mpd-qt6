module MPDUI
  class App
    include FormatHelpers
    include AppTray
    include AppMPDConnection
    include AppAboutDialog
    include AppPlayer
    include AppQueue
    include AppDatabase

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
    @expanded_interface_action : Qt6::Action?
    @show_library_action : Qt6::Action?
    @toggle_window_action : Qt6::Action?
    @browsers : Qt6::Splitter?
    @compact_spacer : Qt6::Widget?
    @expanded_interface_window_minimum_size : Qt6::Size?
    @expanded_interface_window_maximum_size : Qt6::Size?
    @database_panel : Qt6::Widget?
    @tray_icon : Qt6::SystemTrayIcon?
    @tray_menu : Qt6::Menu?
    @database_tree : Qt6::TreeView?
    @database_model : Qt6::StandardItemModel?
    @database_loaded : Bool = false
    @database_loading : Bool = false
    @database_drag_filter : Qt6::EventFilter?
    @queue_drop_filter : Qt6::EventFilter?
    @window_event_filter : Qt6::EventFilter?
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
    @quitting : Bool = false
    @tray_message_shown : Bool = false

    def initialize
      @qt_app = Qt6.application
      @qt_app.name = WINDOW_TITLE
      @settings = Settings.load
      @event_bridge = EventBridge.new(@qt_app)
      bind_event_bridge
    end

    def run : Nil
      build_ui
      connect
      @window.try(&.show)
      exit(@qt_app.run)
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
        column.spacing = 6
        column.set_contents_margins(8, 8, 8, 8)

        cover_label = Qt6::Label.new("No Cover")
        cover_label.set_fixed_size(160, 160)
        cover_label.scaled_contents = false
        cover_label.alignment = Qt6::AlignmentFlag::Center
        cover_label.style_sheet = "background: #222; border: 1px solid #444;"
        cover_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Fixed)

        title_label = Qt6::Label.new("Connecting...")
        title_label.style_sheet = "font-size: 18px; font-weight: bold;"
        title_label.word_wrap = true
        title_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Minimum)

        subtitle_label = Qt6::Label.new("")
        subtitle_label.word_wrap = true
        subtitle_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Minimum)

        progress = Qt6::Widget.new(central)
        progress.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Fixed)
        progress.hbox do |row|
          row.spacing = 6
          row.set_contents_margins(0, 0, 0, 0)

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
        controls.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Fixed)
        controls.hbox do |row|
          row.spacing = 6
          row.set_contents_margins(0, 0, 0, 0)

          prev_button = Qt6::PushButton.new("")
          play_pause_button = Qt6::PushButton.new("")
          next_button = Qt6::PushButton.new("")
          shuffle_button = Qt6::PushButton.new("")
          repeat_button = Qt6::PushButton.new("")

          play_icon = Qt6::QIcon.from_theme("media-playback-start")
          pause_icon = Qt6::QIcon.from_theme("media-playback-pause")
          stop_icon = Qt6::QIcon.from_theme("media-playback-stop")
          prev_icon = Qt6::QIcon.from_theme("media-skip-backward")
          next_icon = Qt6::QIcon.from_theme("media-skip-forward")
          shuffle_icon = Qt6::QIcon.from_theme("media-playlist-shuffle")
          repeat_icon = Qt6::QIcon.from_theme("media-playlist-repeat")
          clear_icon = Qt6::QIcon.from_theme("edit-clear")

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

          row.add_stretch
          row << prev_button
          row << play_pause_button
          row << next_button
          row << shuffle_button
          row << repeat_button
          row.add_stretch

          @play_pause_button = play_pause_button
          @shuffle_button = shuffle_button
          @repeat_button = repeat_button
          @play_icon = play_icon
          @pause_icon = pause_icon
          @stop_icon = stop_icon
        end

        setup_system_tray(window)
        playlist_table = build_playlist(central)
        setup_queue_drop_target(playlist_table)
        database_browser = build_database_browser(central)

        browsers = Qt6::Splitter.new(Qt6::Orientation::Horizontal, central)
        browsers.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Expanding)

        database_panel = Qt6::Widget.new(central)
        database_panel.minimum_width = 220
        database_panel.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Expanding)
        database_panel.vbox do |database_column|
          database_column.spacing = 4
          database_column.set_contents_margins(0, 0, 0, 0)
          database_column << database_browser
        end

        queue_panel = Qt6::Widget.new(central)
        queue_panel.minimum_width = 220
        queue_panel.tool_tip = "Drop songs, albums, or artists here to insert them into the queue"
        queue_panel.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Expanding)
        queue_panel.vbox do |queue_column|
          queue_column.spacing = 4
          queue_column.set_contents_margins(0, 0, 0, 0)
          queue_column << playlist_table
        end

        browsers << database_panel
        browsers << queue_panel

        compact_spacer = Qt6::Widget.new(central)
        compact_spacer.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Expanding)
        compact_spacer.visible = false

        ensure_database_loaded

        column << cover_label
        column << title_label
        column << subtitle_label
        column << progress
        column << controls
        column << browsers
        column << compact_spacer

        @cover_label = cover_label
        @title_label = title_label
        @subtitle_label = subtitle_label
        @browsers = browsers
        @compact_spacer = compact_spacer
        @database_panel = database_panel
        @playlist_table = playlist_table
      end

      window.central_widget = central
      @window = window
      @status_bar = status_bar
      apply_interface_visibility_settings
    end

    private def build_menu(window : Qt6::MainWindow) : Nil
      menu_bar = window.menu_bar

      app_menu = menu_bar.add_menu("&App")
      about_action = Qt6::Action.new("About", window)
      about_icon = Qt6::QIcon.from_theme("help-about")
      about_action.icon = about_icon unless about_icon.null?
      about_action.status_tip = "Show application and MPD server information"
      about_action.on_triggered { open_about_dialog }
      app_menu.add_action(about_action)
      app_menu.add_separator

      expanded_interface_action = Qt6::Action.new("Expanded Interface", window)
      expanded_interface_icon = Qt6::QIcon.from_theme("view-fullscreen")
      expanded_interface_action.icon = expanded_interface_icon unless expanded_interface_icon.null?
      expanded_interface_action.checkable = true
      expanded_interface_action.checked = @settings.expanded_interface
      expanded_interface_action.status_tip = "Show or hide the library and queue panels"
      expanded_interface_action.on_toggled { |checked| set_expanded_interface_visible(checked) }
      app_menu.add_action(expanded_interface_action)
      app_menu.add_separator

      settings_action = Qt6::Action.new("Settings", window)
      settings_icon = Qt6::QIcon.from_theme("preferences-system")
      settings_action.icon = settings_icon unless settings_icon.null?
      settings_action.shortcut = "Ctrl+,"
      settings_action.status_tip = "Open connection settings"
      settings_action.on_triggered { open_settings_dialog }
      app_menu.add_action(settings_action)
      app_menu.add_separator

      quit_action = Qt6::Action.new("Quit", window)
      quit_icon = Qt6::QIcon.from_theme("application-exit")
      quit_action.icon = quit_icon unless quit_icon.null?
      quit_action.shortcut = "Ctrl+Q"
      quit_action.status_tip = "Quit the application"
      quit_action.on_triggered { quit_application }
      app_menu.add_action(quit_action)
      @expanded_interface_action = expanded_interface_action

      library_menu = menu_bar.add_menu("&Library")
      show_library_action = Qt6::Action.new("Show Library", window)
      library_icon = Qt6::QIcon.from_theme("view-list-tree")
      show_library_action.icon = library_icon unless library_icon.null?
      show_library_action.checkable = true
      show_library_action.checked = @settings.show_library
      show_library_action.status_tip = "Show or hide the library panel"
      show_library_action.on_toggled { |checked| set_library_panel_visible(checked) }
      library_menu.add_action(show_library_action)
      library_menu.add_separator

      reload_action = Qt6::Action.new("Reload Database", window)
      reload_icon = Qt6::QIcon.from_theme("view-refresh")
      reload_action.icon = reload_icon unless reload_icon.null?
      reload_action.shortcut = "F5"
      reload_action.status_tip = "Reload the music database from MPD"
      reload_action.on_triggered { ensure_database_loaded(force: true) }
      library_menu.add_action(reload_action)
      @show_library_action = show_library_action

      queue_menu = menu_bar.add_menu("&Queue")
      clear_action = Qt6::Action.new("Clear Queue", window)
      clear_icon = Qt6::QIcon.from_theme("edit-clear")
      clear_action.icon = clear_icon unless clear_icon.null?
      clear_action.shortcut = "Ctrl+L"
      clear_action.status_tip = "Remove all songs from the queue"
      clear_action.on_triggered { clear_queue }
      queue_menu.add_action(clear_action)
    end

    private def apply_interface_visibility_settings : Nil
      if @settings.expanded_interface
        @browsers.try(&.visible = true)
        @compact_spacer.try(&.visible = false)
      else
        set_expanded_interface_visible(false)
      end

      set_library_panel_visible(@settings.show_library)
    end

    private def set_expanded_interface_visible(visible : Bool) : Nil
      if visible
        restore_expanded_interface_window_resize_limits
      end

      @browsers.try(&.visible = visible)
      @compact_spacer.try(&.visible = !visible)
      @window.try(&.adjust_size)

      unless visible
        lock_minimal_window_height
      end

      action = @expanded_interface_action
      action.checked = visible if action && action.checked? != visible

      if @settings.expanded_interface != visible
        @settings.expanded_interface = visible
        @settings.save
      end
    end

    private def lock_minimal_window_height : Nil
      window = @window
      return unless window

      @expanded_interface_window_minimum_size = window.minimum_size
      @expanded_interface_window_maximum_size = window.maximum_size

      size = window.size
      minimum_size = @expanded_interface_window_minimum_size.not_nil!
      maximum_size = @expanded_interface_window_maximum_size.not_nil!
      window.set_minimum_size(minimum_size.width, size.height)
      window.set_maximum_size(maximum_size.width, size.height)
    end

    private def restore_expanded_interface_window_resize_limits : Nil
      window = @window
      return unless window

      if minimum_size = @expanded_interface_window_minimum_size
        window.set_minimum_size(minimum_size.width, minimum_size.height)
      end

      if maximum_size = @expanded_interface_window_maximum_size
        window.set_maximum_size(maximum_size.width, maximum_size.height)
      end
    end

    private def set_library_panel_visible(visible : Bool) : Nil
      @database_panel.try(&.visible = visible)

      action = @show_library_action
      action.checked = visible if action && action.checked? != visible

      if @settings.show_library != visible
        @settings.show_library = visible
        @settings.save
      end
    end

    private def open_settings_dialog : Nil
      parent = @window
      return unless parent

      connect if SettingsDialog.edit(parent, @settings)
    end

    private def set_status(message : String) : Nil
      @status_bar.try(&.show_message(message))
    end
  end
end
