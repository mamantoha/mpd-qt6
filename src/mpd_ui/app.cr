module MPDUI
  class App
    include FormatHelpers
    include AppTray
    include AppMPDConnection
    include AppMPRIS
    include AppLastFM
    include AppAboutDialog
    include AppPlayer
    include AppQueue
    include AppDatabase

    WINDOW_TITLE             = "Crystal MPD"
    COVER_ART_SIZE           = 84
    PROGRESS_ROW_HEIGHT      = 24
    PLAYBACK_CONTROLS_HEIGHT = 56

    @settings : Settings
    @qt_app : Qt6::Application
    @window : Qt6::MainWindow?
    @cover_label : Qt6::Label?
    @title_label : Qt6::Label?
    @subtitle_label : Qt6::Label?
    @status_bar : Qt6::StatusBar?
    @time_label : Qt6::Label?
    @previous_button : Qt6::PushButton?
    @play_pause_button : Qt6::PushButton?
    @next_button : Qt6::PushButton?
    @shuffle_button : Qt6::PushButton?
    @repeat_button : Qt6::PushButton?
    @progress_slider : Qt6::Slider?
    @volume_button : Qt6::PushButton?
    @volume_slider : Qt6::Slider?
    @volume_label : Qt6::Label?
    @volume_menu : Qt6::Menu?
    @volume_widget_action : Qt6::WidgetAction?
    @options_button : Qt6::PushButton?
    @options_menu : Qt6::Menu?
    @playlist_view : Qt6::TreeView?
    @playlist_model : Qt6::StandardItemModel?
    @queue_context_menu : Qt6::Menu?
    @queue_play_now_action : Qt6::Action?
    @play_queue_return_action : Qt6::Action?
    @play_queue_enter_action : Qt6::Action?
    @delete_queue_action : Qt6::Action?
    @about_action : Qt6::Action?
    @settings_action : Qt6::Action?
    @search_library_action : Qt6::Action?
    @reload_database_action : Qt6::Action?
    @expanded_interface_action : Qt6::Action?
    @show_library_action : Qt6::Action?
    @show_main_menu_action : Qt6::Action?
    @blurred_cover_background_action : Qt6::Action?
    @toggle_window_action : Qt6::Action?
    @playback_header : Qt6::Widget?
    @playback_header_background : Qt6::Label?
    @browsers : Qt6::Splitter?
    @compact_spacer : Qt6::Widget?
    @expanded_interface_window_size : Qt6::Size?
    @expanded_interface_window_minimum_size : Qt6::Size?
    @expanded_interface_window_maximum_size : Qt6::Size?
    @database_panel : Qt6::Widget?
    @tray_icon : Qt6::SystemTrayIcon?
    @tray_menu : Qt6::Menu?
    @database_search_panel : Qt6::Widget?
    @database_search_edit : Qt6::LineEdit?
    @database_search_escape_shortcut : Qt6::Shortcut?
    @database_tree : Qt6::TreeView?
    @database_context_menu : Qt6::Menu?
    @database_model : Qt6::StandardItemModel?
    @database_item_delegate : Qt6::StyledItemDelegate?
    @database_songs : Array(Song) = [] of Song
    @database_loaded : Bool = false
    @database_loading : Bool = false
    @database_drag_filter : Qt6::EventFilter?
    @queue_drop_filter : Qt6::EventFilter?
    @progress_tooltip_filter : Qt6::EventFilter?
    @cover_click_filter : Qt6::EventFilter?
    @window_event_filter : Qt6::EventFilter?
    @playlist_drag_source_row : Int32? = nil
    @dragged_database_uris : Array(String) = [] of String
    # Track drag source: :playlist, :database, or nil
    @drag_source_type : Symbol? = nil
    @client : MPD::Client?
    @callback_client : MPD::Client?
    @event_bridge : EventBridge
    @mpris_service : MPRIS::Service?
    @lastfm_scrobbler : LastFM::Scrobbler?
    @callback_generation : Atomic(Int32) = Atomic(Int32).new(0)
    @play_icon : Qt6::QIcon?
    @pause_icon : Qt6::QIcon?
    @stop_icon : Qt6::QIcon?
    @playback_state : PlaybackState = PlaybackState.new
    @playlist_positions : Array(Int32) = [] of Int32
    @playlist_ids : Array(Int32) = [] of Int32
    @just_moved_pos : Int32? = nil
    @status_refresh_pending : Atomic(Bool) = Atomic(Bool).new(false)
    @syncing : Bool = false
    @syncing_progress : Bool = false
    @syncing_volume : Bool = false
    @dragging_progress : Bool = false
    @current_file : String = ""
    @mpris_song : Song?
    @mpris_art_url : String = ""
    @mpris_cover_path : String?
    @mpris_last_position_second : Int64? = nil
    @cover_art_generation : Atomic(Int32) = Atomic(Int32).new(0)
    @quitting : Bool = false
    @tray_message_shown : Bool = false

    def initialize
      @qt_app = Qt6.application
      @qt_app.name = WINDOW_TITLE
      @settings = Settings.load
      if width = @settings.expanded_window_width
        if height = @settings.expanded_window_height
          @expanded_interface_window_size = Qt6::Size.new(width, height)
        end
      end
      @event_bridge = EventBridge.new(@qt_app)
      bind_event_bridge
      setup_lastfm
    end

    def run : Nil
      build_ui
      setup_mpris
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
        column.spacing = 0
        column.set_contents_margins(0, 0, 0, 0)

        cover_label = Qt6::Label.new("No Cover")
        cover_label.set_fixed_size(COVER_ART_SIZE, COVER_ART_SIZE)
        cover_label.scaled_contents = false
        cover_label.alignment = Qt6::AlignmentFlag::Center
        cover_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Fixed)
        cover_label.cursor_shape = Qt6::CursorShape::PointingHand
        setup_cover_art_toggle(cover_label)

        options_button = Qt6::PushButton.new("...")
        options_menu = Qt6::Menu.new("Options", options_button)
        options_icon = Qt6::QIcon.from_theme("open-menu-symbolic")
        unless options_icon.null?
          options_button.icon = options_icon
          options_button.text = ""
        end
        options_button.icon_size = Qt6::Size.new(22, 22)
        options_button.fixed_width = 44
        options_button.tool_tip = "Options"
        options_button.style_sheet = "QPushButton::menu-indicator { image: none; width: 0px; }"
        options_button.flat = true
        if settings_action = @settings_action
          options_menu.add_action(settings_action)
        end
        if search_library_action = @search_library_action
          options_menu.add_action(search_library_action)
        end
        if reload_database_action = @reload_database_action
          options_menu.add_action(reload_database_action)
        end
        options_menu.add_separator
        if show_library_action = @show_library_action
          options_menu.add_action(show_library_action)
        end
        if expanded_interface_action = @expanded_interface_action
          options_menu.add_action(expanded_interface_action)
        end
        if blurred_cover_background_action = @blurred_cover_background_action
          options_menu.add_action(blurred_cover_background_action)
        end
        options_menu.add_separator
        if show_main_menu_action = @show_main_menu_action
          options_menu.add_action(show_main_menu_action)
        end
        options_menu.add_separator
        if about_action = @about_action
          options_menu.add_action(about_action)
        end
        options_button.menu = options_menu

        title_label = Qt6::Label.new("Connecting...")
        title_label.style_sheet = "font-size: 16px; font-weight: bold;"
        title_label.word_wrap = true
        title_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Minimum)

        subtitle_label = Qt6::Label.new("")
        subtitle_label.word_wrap = true
        subtitle_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Minimum)

        progress = Qt6::Widget.new(central)
        progress.fixed_height = PROGRESS_ROW_HEIGHT
        progress.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
        progress.hbox do |row|
          row.spacing = 6
          row.set_contents_margins(0, 0, 0, 0)

          progress_slider = Qt6::Slider.new(Qt6::Orientation::Horizontal)
          progress_slider.set_range(0, 1000)
          progress_slider.value = 0
          progress_slider.minimum_width = 320
          progress_slider.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
          progress_slider.click_to_position = true
          setup_progress_tooltip(progress_slider)

          time_label = Qt6::Label.new("0:00 / 0:00")
          time_label.set_size_policy(Qt6::SizePolicy::Fixed, Qt6::SizePolicy::Fixed)

          progress_slider.on_pressed do
            @dragging_progress = true
          end

          progress_slider.on_value_changed do |value|
            duration = @playback_state.duration
            next if @syncing_progress || duration <= 0
            @dragging_progress = true
            target = duration * value / 1000.0
            @time_label.try(&.text = "#{format_time(target)} / #{format_time(duration)}")
            show_progress_tooltip(progress_slider, slider_position_for_value(progress_slider, value), target)
          end

          progress_slider.on_released do
            @dragging_progress = false
            duration = @playback_state.duration
            next if @syncing_progress || duration <= 0

            Qt6::ToolTip.hide_text
            target = duration * progress_slider.value / 1000.0
            mpd_action { |c| c.seekcur(target.to_i) }
          end

          row << progress_slider
          row << time_label

          @progress_slider = progress_slider
          @time_label = time_label
        end

        controls = Qt6::Widget.new(central)
        controls.fixed_height = PLAYBACK_CONTROLS_HEIGHT
        controls.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Fixed)
        controls.hbox do |row|
          row.spacing = 6
          row.set_contents_margins(0, 0, 0, 0)

          prev_button = Qt6::PushButton.new("")
          play_pause_button = Qt6::PushButton.new("")
          next_button = Qt6::PushButton.new("")
          shuffle_button = Qt6::PushButton.new("")
          repeat_button = Qt6::PushButton.new("")
          volume_button = Qt6::PushButton.new("")
          volume_menu = Qt6::Menu.new("Volume", volume_button)
          volume_panel = Qt6::Widget.new(volume_menu)
          volume_slider = Qt6::Slider.new(Qt6::Orientation::Vertical, volume_panel)
          volume_label = Qt6::Label.new("--%", volume_panel)
          volume_widget_action = Qt6::WidgetAction.new(volume_menu)

          play_icon = Qt6::QIcon.from_theme("media-playback-start")
          pause_icon = Qt6::QIcon.from_theme("media-playback-pause")
          stop_icon = Qt6::QIcon.from_theme("media-playback-stop")
          prev_icon = Qt6::QIcon.from_theme("media-skip-backward")
          next_icon = Qt6::QIcon.from_theme("media-skip-forward")
          shuffle_icon = Qt6::QIcon.from_theme("media-playlist-shuffle")
          repeat_icon = Qt6::QIcon.from_theme("media-playlist-repeat")
          clear_icon = Qt6::QIcon.from_theme("edit-clear")
          volume_icon = Qt6::QIcon.from_theme("audio-volume-medium")

          prev_button.icon = prev_icon
          play_pause_button.icon = play_icon
          next_button.icon = next_icon
          shuffle_button.icon = shuffle_icon unless shuffle_icon.null?
          repeat_button.icon = repeat_icon unless repeat_icon.null?
          volume_button.icon = volume_icon unless volume_icon.null?
          prev_button.icon_size = Qt6::Size.new(22, 22)
          play_pause_button.icon_size = Qt6::Size.new(22, 22)
          next_button.icon_size = Qt6::Size.new(22, 22)
          shuffle_button.icon_size = Qt6::Size.new(22, 22)
          repeat_button.icon_size = Qt6::Size.new(22, 22)
          volume_button.icon_size = Qt6::Size.new(22, 22)
          prev_button.fixed_width = 44
          play_pause_button.fixed_width = 44
          next_button.fixed_width = 44
          shuffle_button.fixed_width = 44
          repeat_button.fixed_width = 44
          volume_button.fixed_width = 44

          prev_button.flat = true
          play_pause_button.flat = true
          next_button.flat = true
          shuffle_button.flat = true
          repeat_button.flat = true
          volume_button.flat = true

          prev_button.tool_tip = "Previous"
          play_pause_button.tool_tip = "Play/Pause"
          next_button.tool_tip = "Next"
          shuffle_button.tool_tip = "Shuffle"
          repeat_button.tool_tip = "Repeat"
          volume_button.tool_tip = "Volume"
          volume_button.style_sheet = "QPushButton::menu-indicator { image: none; width: 0px; }"
          volume_slider.tool_tip = "Volume"
          volume_slider.set_range(0, 100)
          volume_slider.value = 0
          volume_slider.set_fixed_size(36, 132)
          volume_slider.enabled = false
          volume_slider.click_to_position = true
          volume_label.alignment = Qt6::AlignmentFlag::Center
          volume_label.tool_tip = "Volume"
          volume_panel.vbox do |volume_column|
            volume_column.set_contents_margins(8, 8, 8, 8)
            volume_column << volume_slider
            volume_column << volume_label
          end
          volume_widget_action.default_widget = volume_panel
          volume_menu.add_action(volume_widget_action)
          volume_button.menu = volume_menu

          shuffle_button.checkable = true
          repeat_button.checkable = true

          prev_button.on_clicked { mpd_action { |c| c.previous } }
          play_pause_button.on_clicked { toggle_play_pause }
          next_button.on_clicked { mpd_action { |c| c.next } }
          shuffle_button.on_toggled do |checked|
            next if @syncing

            mpd_action { |c| c.random(checked) }
          end
          repeat_button.on_toggled do |checked|
            next if @syncing

            mpd_action { |c| c.repeat(checked) }
          end
          volume_slider.on_value_changed do |value|
            next if @syncing_volume

            mpd_action { |c| c.setvol(value) }
          end

          row.add_stretch
          row << prev_button
          row << play_pause_button
          row << next_button
          row << shuffle_button
          row << repeat_button
          row << volume_button
          row.add_stretch

          @previous_button = prev_button
          @play_pause_button = play_pause_button
          @next_button = next_button
          @shuffle_button = shuffle_button
          @repeat_button = repeat_button
          @volume_button = volume_button
          @volume_slider = volume_slider
          @volume_label = volume_label
          @volume_menu = volume_menu
          @volume_widget_action = volume_widget_action
          @play_icon = play_icon
          @pause_icon = pause_icon
          @stop_icon = stop_icon
        end

        metadata_panel = Qt6::Widget.new(central)
        metadata_panel.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
        metadata_panel.vbox do |metadata_column|
          metadata_column.spacing = 2
          metadata_column.set_contents_margins(0, 0, 0, 0)
          metadata_column << title_label
          metadata_column << subtitle_label
        end

        options_panel = Qt6::Widget.new(central)
        options_panel.set_size_policy(Qt6::SizePolicy::Fixed, Qt6::SizePolicy::Preferred)
        options_panel.vbox do |options_column|
          options_column.set_contents_margins(0, 0, 0, 0)
          options_column << options_button
          options_column.add_stretch
        end

        header_body = Qt6::Widget.new(central)
        header_body.fixed_height = COVER_ART_SIZE
        header_body.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
        header_body.grid do |grid|
          grid.spacing = 10
          grid.set_contents_margins(0, 0, 0, 0)
          grid.add(cover_label, 0, 0, 2, 1)
          grid.add(metadata_panel, 0, 1)
          grid.add(options_panel, 0, 2)
          grid.add(progress, 1, 1, 1, 2)
        end

        playback_header = Qt6::EventWidget.new(central)
        playback_header.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
        playback_header_background = Qt6::Label.new("", playback_header)
        playback_header_background.scaled_contents = true
        playback_header_background.transparent_for_mouse_events = true
        playback_header_background.visible = false
        blur = Qt6::GraphicsBlurEffect.new(playback_header_background)
        blur.blur_radius = 18
        playback_header_background.graphics_effect = blur

        playback_header_content = Qt6::Widget.new(playback_header)
        playback_header_content.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
        playback_header_content.vbox do |header_column|
          header_column.spacing = 8
          header_column.set_contents_margins(8, 8, 8, 8)
          header_column << header_body
          header_column << controls
        end
        playback_header.vbox do |header_column|
          header_column.set_contents_margins(0, 0, 0, 0)
          header_column << playback_header_content
        end
        playback_header.on_resize do |event|
          playback_header_background.resize(event.size.width, event.size.height)
          playback_header_background.move(0, 0)
          playback_header_content.raise_to_front
        end
        playback_header_content.raise_to_front

        setup_system_tray(window)
        playlist_view = build_playlist(central)
        setup_queue_drop_target(playlist_view)
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
          queue_column << playlist_view
        end

        browsers << database_panel
        browsers << queue_panel
        restore_library_queue_splitter_sizes(browsers)

        compact_spacer = Qt6::Widget.new(central)
        compact_spacer.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Expanding)
        compact_spacer.visible = false

        ensure_database_loaded

        column << playback_header
        column << browsers
        column << compact_spacer

        @cover_label = cover_label
        @title_label = title_label
        @subtitle_label = subtitle_label
        @options_button = options_button
        @options_menu = options_menu
        @playback_header = playback_header
        @playback_header_background = playback_header_background
        @browsers = browsers
        @compact_spacer = compact_spacer
        @database_panel = database_panel
        @playlist_view = playlist_view
        sync_playback_controls
      end

      window.central_widget = central
      @window = window
      @status_bar = status_bar
      apply_interface_visibility_settings
      restore_expanded_window_size if @settings.expanded_interface
    end

    private def build_menu(window : Qt6::MainWindow) : Nil
      menu_bar = window.menu_bar

      app_menu = menu_bar.add_menu("&App")
      about_action = Qt6::Action.new("About", window)
      about_icon = Qt6::QIcon.from_theme("help-about")
      about_action.icon = about_icon unless about_icon.null?
      about_action.on_triggered { open_about_dialog }
      app_menu.add_action(about_action)
      app_menu.add_separator

      expanded_interface_action = Qt6::Action.new("Expanded Interface", window)
      expanded_interface_icon = Qt6::QIcon.from_theme("view-fullscreen")
      expanded_interface_action.icon = expanded_interface_icon unless expanded_interface_icon.null?
      expanded_interface_action.checkable = true
      expanded_interface_action.checked = @settings.expanded_interface
      expanded_interface_action.on_toggled { |checked| set_expanded_interface_visible(checked) }
      app_menu.add_action(expanded_interface_action)

      blurred_cover_background_action = Qt6::Action.new("Blurred Cover Background", window)
      blurred_cover_icon = Qt6::QIcon.from_theme("image-x-generic")
      blurred_cover_background_action.icon = blurred_cover_icon unless blurred_cover_icon.null?
      blurred_cover_background_action.checkable = true
      blurred_cover_background_action.checked = @settings.blurred_cover_background
      blurred_cover_background_action.on_toggled { |checked| set_blurred_cover_background_enabled(checked) }
      app_menu.add_action(blurred_cover_background_action)
      app_menu.add_separator

      show_main_menu_action = Qt6::Action.new("Show Main Menu", window)
      main_menu_icon = Qt6::QIcon.from_theme("show-menu")
      show_main_menu_action.icon = main_menu_icon unless main_menu_icon.null?
      show_main_menu_action.checkable = true
      show_main_menu_action.checked = @settings.show_main_menu
      show_main_menu_action.shortcut = "Ctrl+M"
      show_main_menu_action.on_toggled do |checked|
        window.menu_bar.visible = checked
        if @settings.show_main_menu != checked
          @settings.show_main_menu = checked
          @settings.save
        end
      end
      app_menu.add_action(show_main_menu_action)
      window.add_action(show_main_menu_action)
      window.menu_bar.visible = @settings.show_main_menu
      app_menu.add_separator

      settings_action = Qt6::Action.new("Settings", window)
      settings_icon = Qt6::QIcon.from_theme("preferences-system")
      settings_action.icon = settings_icon unless settings_icon.null?
      settings_action.shortcut = "Ctrl+,"
      settings_action.on_triggered { open_settings_dialog }
      app_menu.add_action(settings_action)
      window.add_action(settings_action)
      app_menu.add_separator

      quit_action = Qt6::Action.new("Quit", window)
      quit_icon = Qt6::QIcon.from_theme("application-exit")
      quit_action.icon = quit_icon unless quit_icon.null?
      quit_action.shortcut = "Ctrl+Q"
      quit_action.on_triggered { quit_application }
      app_menu.add_action(quit_action)
      window.add_action(quit_action)
      @about_action = about_action
      @expanded_interface_action = expanded_interface_action
      @blurred_cover_background_action = blurred_cover_background_action
      @show_main_menu_action = show_main_menu_action
      @settings_action = settings_action

      library_menu = menu_bar.add_menu("&Library")
      show_library_action = Qt6::Action.new("Show Library", window)
      library_icon = Qt6::QIcon.from_theme("view-list-tree")
      show_library_action.icon = library_icon unless library_icon.null?
      show_library_action.checkable = true
      show_library_action.checked = @settings.show_library
      show_library_action.on_toggled { |checked| set_library_panel_visible(checked) }
      library_menu.add_action(show_library_action)
      library_menu.add_separator

      search_library_action = Qt6::Action.new("Search Library", window)
      search_icon = Qt6::QIcon.from_theme("edit-find")
      search_library_action.icon = search_icon unless search_icon.null?
      search_library_action.shortcut = "Ctrl+F"
      search_library_action.on_triggered { show_database_search }
      library_menu.add_action(search_library_action)
      window.add_action(search_library_action)
      @search_library_action = search_library_action
      library_menu.add_separator

      reload_action = Qt6::Action.new("Reload Database", window)
      reload_icon = Qt6::QIcon.from_theme("view-refresh")
      reload_action.icon = reload_icon unless reload_icon.null?
      reload_action.shortcut = "F5"
      reload_action.on_triggered { ensure_database_loaded(force: true, update_mpd: true) }
      library_menu.add_action(reload_action)
      window.add_action(reload_action)
      @show_library_action = show_library_action
      @reload_database_action = reload_action

      queue_menu = menu_bar.add_menu("&Queue")
      clear_action = Qt6::Action.new("Clear Queue", window)
      clear_icon = Qt6::QIcon.from_theme("edit-clear")
      clear_action.icon = clear_icon unless clear_icon.null?
      clear_action.shortcut = "Ctrl+L"
      clear_action.on_triggered { clear_queue }
      queue_menu.add_action(clear_action)
      window.add_action(clear_action)
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
      window = @window

      if visible
        restore_expanded_interface_window_resize_limits
      elsif window && @settings.expanded_interface
        save_expanded_layout_settings
        @expanded_interface_window_size = window.size
      end

      @browsers.try(&.visible = visible)
      @compact_spacer.try(&.visible = !visible)

      if window
        window.adjust_size
        if visible
          if expanded_size = @expanded_interface_window_size
            window.resize(expanded_size.width, expanded_size.height)
            @expanded_interface_window_size = nil
          end
        elsif expanded_size = @expanded_interface_window_size
          window.resize(expanded_size.width, window.size.height)
        end
      end

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

    private def set_blurred_cover_background_enabled(enabled : Bool) : Nil
      action = @blurred_cover_background_action
      action.checked = enabled if action && action.checked? != enabled

      if @settings.blurred_cover_background != enabled
        @settings.blurred_cover_background = enabled
        @settings.save
      end

      if enabled
        request_cover_art(@current_file, @mpris_song) unless @current_file.empty?
      else
        reset_cover_background
      end
    end

    private def setup_cover_art_toggle(cover_label : Qt6::Label) : Nil
      filter = Qt6::EventFilter.new(cover_label)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonRelease
          mouse_event = event.mouse_event
          if mouse_event.button == 1
            Qt6::ToolTip.hide_text
            toggle_expanded_interface
            true
          else
            false
          end
        else
          false
        end
      end

      cover_label.install_event_filter(filter)
      @cover_click_filter = filter
    end

    private def toggle_expanded_interface : Nil
      action = @expanded_interface_action
      if action
        action.checked = !action.checked?
      else
        set_expanded_interface_visible(!@settings.expanded_interface)
      end
    end

    private def lock_minimal_window_height : Nil
      window = @window
      return unless window

      @expanded_interface_window_minimum_size ||= window.minimum_size
      @expanded_interface_window_maximum_size ||= window.maximum_size

      size = window.size
      minimum_size = @expanded_interface_window_minimum_size.not_nil!
      maximum_size = @expanded_interface_window_maximum_size.not_nil!
      window.set_minimum_size(minimum_size.width, size.height)
      window.set_maximum_size(maximum_size.width, size.height)
    end

    private def restore_expanded_window_size : Nil
      window = @window
      expanded_size = @expanded_interface_window_size
      return unless window && expanded_size

      window.resize(expanded_size.width, expanded_size.height)
    end

    private def restore_library_queue_splitter_sizes(splitter : Qt6::Splitter) : Nil
      sizes = @settings.library_queue_splitter_sizes
      return unless sizes.size == 2 && sizes.all? { |size| size > 0 }

      splitter.set_sizes(sizes)
    end

    private def save_expanded_layout_settings : Nil
      if @settings.expanded_interface
        if window = @window
          size = window.size
          @settings.expanded_window_width = size.width
          @settings.expanded_window_height = size.height
          @expanded_interface_window_size = size
        end

        if splitter = @browsers
          sizes = splitter.sizes
          @settings.library_queue_splitter_sizes = sizes if sizes.size == 2 && sizes.all? { |size| size > 0 }
        end
      elsif expanded_size = @expanded_interface_window_size
        @settings.expanded_window_width = expanded_size.width
        @settings.expanded_window_height = expanded_size.height
      end

      @settings.save
    end

    private def restore_expanded_interface_window_resize_limits : Nil
      window = @window
      return unless window

      if maximum_size = @expanded_interface_window_maximum_size
        window.set_maximum_size(maximum_size.width, maximum_size.height)
      end

      if minimum_size = @expanded_interface_window_minimum_size
        window.set_minimum_size(minimum_size.width, minimum_size.height)
      end

      @expanded_interface_window_minimum_size = nil
      @expanded_interface_window_maximum_size = nil
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

      if SettingsDialog.edit(parent, @settings)
        setup_lastfm
        connect
      end
    end

    private def setup_progress_tooltip(slider : Qt6::Slider) : Nil
      slider.mouse_tracking = true

      filter = Qt6::EventFilter.new(slider)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseMove
          show_progress_tooltip(slider, event.mouse_event.position)
          false
        when Qt6::EventType::Leave
          @dragging_progress = false
          slider.tool_tip = ""
          Qt6::ToolTip.hide_text
          false
        else
          false
        end
      end

      slider.install_event_filter(filter)
      @progress_tooltip_filter = filter
    end

    private def show_progress_tooltip(slider : Qt6::Slider, position : Qt6::PointF, seconds : Float64? = nil) : Nil
      duration = @playback_state.duration
      if duration <= 0
        slider.tool_tip = ""
        Qt6::ToolTip.hide_text
        return
      end

      width = slider.size.width
      return if width <= 0

      x = position.x.clamp(0.0, width.to_f64)
      target = seconds || (duration * x / width)
      text = format_time(target)
      slider.tool_tip = text
      Qt6::ToolTip.show_text(slider, Qt6::PointF.new(x, 0.0), text)
    end

    private def slider_position_for_value(slider : Qt6::Slider, value : Int32) : Qt6::PointF
      width = slider.size.width
      x = width > 0 ? (width * value / 1000.0).clamp(0.0, width.to_f64) : 0.0
      Qt6::PointF.new(x, 0.0)
    end

    private def set_status(message : String) : Nil
      @status_bar.try(&.show_message(message))
    end
  end
end
