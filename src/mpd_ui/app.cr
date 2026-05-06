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
    include BackgroundTask

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
    @player_header_view : PlayerHeaderView?
    @queue_view : QueueView?
    @queue_controller : QueueController
    @playlist_view : Qt6::TreeView?
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
    @library_view : LibraryView?
    @library_index : LibraryIndex
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
    @player_controller : PlayerController
    @mpris_adapter : MprisAdapter?
    @lastfm_adapter : LastfmAdapter?
    @callback_generation : Atomic(Int32) = Atomic(Int32).new(0)
    @play_icon : Qt6::QIcon?
    @pause_icon : Qt6::QIcon?
    @stop_icon : Qt6::QIcon?
    @playback_state : PlaybackState = PlaybackState.new
    @just_moved_pos : Int32? = nil
    @status_refresh_pending : Atomic(Bool) = Atomic(Bool).new(false)
    @syncing : Bool = false
    @syncing_volume : Bool = false
    @current_file : String = ""
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
      @player_controller = PlayerController.new(-> { @client })
      @queue_controller = QueueController.new
      @library_index = LibraryIndex.new
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

        player_header = PlayerHeaderView.new(
          central,
          COVER_ART_SIZE,
          PROGRESS_ROW_HEIGHT,
          PLAYBACK_CONTROLS_HEIGHT,
          @settings_action,
          @search_library_action,
          @reload_database_action,
          @show_library_action,
          @expanded_interface_action,
          @blurred_cover_background_action,
          @show_main_menu_action,
          @about_action
        )
        player_header.on_previous = -> { mpd_action(&.previous) }
        player_header.on_play_pause = -> { toggle_play_pause }
        player_header.on_next = -> { mpd_action(&.next) }
        player_header.on_shuffle_changed = ->(checked : Bool) { mpd_action(&.random(checked)) unless @syncing }
        player_header.on_repeat_changed = ->(checked : Bool) { mpd_action(&.repeat(checked)) unless @syncing }
        player_header.on_volume_changed = ->(value : Int32) { mpd_action(&.setvol(value)) unless @syncing_volume }
        player_header.on_seek = ->(seconds : Int32) { mpd_action(&.seekcur(seconds)) }
        player_header.on_cover_clicked = -> { toggle_expanded_interface }

        setup_system_tray(window)
        queue_view = build_playlist(central)
        playlist_view = queue_view.view
        setup_queue_drop_target(queue_view)
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

        column << player_header.root
        column << browsers
        column << compact_spacer

        @player_header_view = player_header
        @cover_label = player_header.cover_label
        @title_label = player_header.title_label
        @subtitle_label = player_header.subtitle_label
        @progress_slider = player_header.progress_slider
        @time_label = player_header.time_label
        @previous_button = player_header.previous_button
        @play_pause_button = player_header.play_pause_button
        @next_button = player_header.next_button
        @shuffle_button = player_header.shuffle_button
        @repeat_button = player_header.repeat_button
        @volume_button = player_header.volume_button
        @volume_slider = player_header.volume_slider
        @volume_label = player_header.volume_label
        @play_icon = player_header.play_icon
        @pause_icon = player_header.pause_icon
        @stop_icon = player_header.stop_icon
        @playback_header = player_header.root
        @playback_header_background = player_header.background
        @browsers = browsers
        @compact_spacer = compact_spacer
        @database_panel = database_panel
        @queue_view = queue_view
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
        request_cover_art(@current_file, @mpris_adapter.try(&.song)) unless @current_file.empty?
      else
        reset_cover_background
      end
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

    private def set_status(message : String) : Nil
      @status_bar.try(&.show_message(message))
    end
  end
end
