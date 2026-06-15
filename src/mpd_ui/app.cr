module MPDUI
  class App
    include FormatHelpers
    include AppWindowEvents
    include AppTray
    include AppMPDConnection
    include AppMPRIS
    include AppLastFM
    include AppOutputs
    include AppAboutDialog
    include AppPlayer
    include AppQueue
    include AppDatabase
    include AppPlaylists
    include AppLyrics
    include BackgroundTask

    WINDOW_TITLE             = Settings::DISPLAY_NAME
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
    @app_actions : AppActions?
    @app_layout_view : AppLayoutView?
    @player_header_view : PlayerHeaderView?
    @queue_view : QueueView?
    @queue_controller : QueueController
    @queue_commands : QueueCommandService
    @stored_playlists : StoredPlaylistService
    @playlist_view : Qt6::TreeView?
    @toggle_window_action : Qt6::Action?
    @playback_header : Qt6::Widget?
    @playback_header_background : Qt6::Label?
    @browsers : Qt6::Splitter?
    @compact_spacer : Qt6::Widget?
    @last_expanded_window_size : Qt6::Size?
    @expanded_interface_window_size : Qt6::Size?
    @expanded_interface_window_minimum_size : Qt6::Size?
    @expanded_interface_window_maximum_size : Qt6::Size?
    @database_panel : Qt6::Widget?
    @lyrics_panel : Qt6::Widget?
    @library_tabs : Qt6::TabWidget?
    @tray_icon : Qt6::SystemTrayIcon?
    @tray_menu : Qt6::Menu?
    @library_view : LibraryView?
    @lyrics_view : LyricsView?
    @lyrics_service : LyricsService
    @lyrics_song_key : String?
    @playlists_view : PlaylistsView?
    @library_index : LibraryIndex
    @database_loaded : Bool = false
    @database_loading : Bool = false
    @database_drag_filter : Qt6::EventFilter?
    @database_filter_timer : Qt6::QTimer?
    @last_database_filter_query : String? = nil
    @last_database_filter_genre : String? = nil
    @database_filter_generation : Atomic(Int32) = Atomic(Int32).new(0)
    @queue_drop_filter : Qt6::EventFilter?
    @window_event_filter : Qt6::EventFilter?
    @output_actions : Array(Qt6::Action) = [] of Qt6::Action
    @drag_context : DragContext
    @client : MPD::Client?
    @callback_client : MPD::Client?
    @stored_playlist_idle_client : MPD::Client?
    @event_bridge : EventBridge
    @player_controller : PlayerController
    @visualizer_service : VisualizerService
    @mpris_adapter : MprisAdapter?
    @lastfm_adapter : LastfmAdapter?
    @callback_generation : Atomic(Int32) = Atomic(Int32).new(0)
    @connection_generation : Atomic(Int32) = Atomic(Int32).new(0)
    @play_icon : Qt6::QIcon?
    @pause_icon : Qt6::QIcon?
    @stop_icon : Qt6::QIcon?
    @playback_state : PlaybackState = PlaybackState.new
    @just_moved_pos : Int32? = nil
    @preserve_queue_scroll_once : Bool = false
    @status_refresh_pending : Atomic(Bool) = Atomic(Bool).new(false)
    @status_retry_scheduled : Bool = false
    @waiting_for_mpd_status : Bool = false
    @mpd_available : Bool = false
    @syncing : Bool = false
    @syncing_volume : Bool = false
    @current_file : String = ""
    @cover_art_generation : Atomic(Int32) = Atomic(Int32).new(0)
    @quitting : Bool = false
    @tray_message_shown : Bool = false

    def initialize
      @qt_app = Qt6.application
      @qt_app.name = WINDOW_TITLE
      # I18n.install_default
      @settings = Settings.load
      if width = @settings.expanded_window_width
        if height = @settings.expanded_window_height
          size = Qt6::Size.new(width, height)
          @expanded_interface_window_size = size
          @last_expanded_window_size = size
        end
      end
      @event_bridge = EventBridge.new(@qt_app)
      @player_controller = PlayerController.new(-> { @client })
      @visualizer_service = VisualizerService.new
      @lyrics_service = LyricsService.new(
        LRCLIB::Client.new(user_agent: Settings::DISPLAY_NAME),
        LyricsCache.new(Settings::CACHE_PREFIX),
        ->(callback : Proc(Nil)) {
          @qt_app.invoke_later do
            callback.call unless @quitting
          end
        }
      )
      @drag_context = DragContext.new
      apply_visualizer_settings
      @queue_controller = QueueController.new
      @queue_commands = QueueCommandService.new
      @stored_playlists = StoredPlaylistService.new
      @library_index = LibraryIndex.new
      bind_event_bridge
      setup_lastfm
    end

    def run : Nil
      build_ui
      setup_mpris
      @visualizer_service.start
      connect
      if @settings.expanded_interface? && @settings.expanded_window_maximized?
        @window.try(&.show_maximized)
      else
        @window.try(&.show)
      end

      exit_code = @qt_app.run
      shutdown_application
      Process.exit(exit_code)
    end

    private def build_ui : Nil
      window = Qt6::MainWindow.new
      window.menu_bar.visible = @settings.show_main_menu?
      window.window_title = WINDOW_TITLE
      window.resize(700, 720)

      actions = build_actions(window)
      build_menu(window, actions)
      status_bar = window.status_bar
      status_bar.show_message("Ready")

      player_header = build_player_header(window, actions)
      install_window_event_filter(window)
      setup_system_tray(window)
      queue_view = build_playlist(window)
      setup_queue_drop_target(queue_view)
      database_browser = build_database_browser(window)
      lyrics_view = LyricsView.new(window)
      lyrics_view.on_seek = ->(seconds : Int32) { seek_from_lyrics(seconds) }
      playlists = build_playlists(window)
      library_tabs = Qt6::TabWidget.new(window)
      library_tabs.add_tab(database_browser, "Library")
      library_tabs.add_tab(playlists.root, "Playlists")
      layout = AppLayoutView.new(window, player_header, library_tabs, lyrics_view.root, queue_view)
      restore_library_queue_splitter_sizes(layout.browsers)

      @app_layout_view = layout
      @player_header_view = player_header
      @browsers = layout.browsers
      @compact_spacer = layout.compact_spacer
      @database_panel = layout.database_panel
      @lyrics_panel = layout.lyrics_panel
      @library_tabs = library_tabs
      @lyrics_view = lyrics_view
      @queue_view = queue_view
      @playlist_view = queue_view.view
      assign_player_header_references(player_header)
      ensure_database_loaded
      sync_playback_controls

      window.central_widget = layout.central
      @window = window
      @status_bar = status_bar
      apply_interface_visibility_settings
      restore_expanded_window_size if @settings.expanded_interface?
    end

    private def build_actions(window : Qt6::MainWindow) : AppActions
      actions = AppActions.new(window, @settings)
      bind_app_actions(window, actions)
      install_window_actions(window, actions)
      @app_actions = actions
      actions
    end

    private def bind_app_actions(window : Qt6::MainWindow, actions : AppActions) : Nil
      actions.about.on_triggered { open_about_dialog }
      actions.expanded_interface.on_toggled { |checked| set_expanded_interface_visible(checked) }
      actions.blurred_cover_background.on_toggled { |checked| set_blurred_cover_background_enabled(checked) }
      actions.show_main_menu.on_toggled do |checked|
        window.menu_bar.visible = checked
        if @settings.show_main_menu? != checked
          @settings.show_main_menu = checked
          @settings.save
        end
      end
      actions.settings.on_triggered { open_settings_dialog }
      actions.outputs.on_triggered { refresh_outputs_menu }
      actions.quit.on_triggered { quit_application }
      actions.show_library.on_toggled { |checked| set_library_panel_visible(checked) }
      actions.show_lyrics.on_toggled { |checked| set_lyrics_panel_visible(checked) }
      actions.search_library.on_triggered { show_database_search }
      actions.reload_database.on_triggered { ensure_database_loaded(force: true, update_mpd: true) }
      actions.save_queue_as_playlist.on_triggered { save_queue_as_playlist }
      actions.clear_queue.on_triggered { clear_queue }
    end

    private def install_window_actions(window : Qt6::MainWindow, actions : AppActions) : Nil
      window.add_action(actions.show_main_menu)
      window.add_action(actions.settings)
      window.add_action(actions.quit)
      window.add_action(actions.search_library)
      window.add_action(actions.reload_database)
      window.add_action(actions.clear_queue)
    end

    private def build_menu(window : Qt6::MainWindow, actions : AppActions) : Nil
      ApplicationMenu.new(window, actions)
    end

    private def build_player_header(parent : Qt6::Widget, actions : AppActions) : PlayerHeaderView
      player_header = PlayerHeaderView.new(
        parent,
        COVER_ART_SIZE,
        PROGRESS_ROW_HEIGHT,
        PLAYBACK_CONTROLS_HEIGHT,
        actions,
        @visualizer_service
      )
      player_header.on_previous = -> { mpd_action(&.previous) }
      player_header.on_play_pause = -> { toggle_play_pause }
      player_header.on_next = -> { mpd_action(&.next) }
      player_header.on_shuffle_changed = ->(checked : Bool) { mpd_action(&.random(checked)) unless @syncing }
      player_header.on_repeat_changed = ->(checked : Bool) { mpd_action(&.repeat(checked)) unless @syncing }
      player_header.on_volume_changed = ->(value : Int32) { mpd_action(&.setvol(value)) unless @syncing_volume }
      player_header.on_seek = ->(seconds : Int32) { mpd_action(&.seekcur(seconds)) }
      player_header.on_cover_clicked = -> { toggle_expanded_interface }
      player_header
    end

    private def assign_player_header_references(player_header : PlayerHeaderView) : Nil
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
    end

    private def apply_interface_visibility_settings : Nil
      if @settings.expanded_interface?
        @browsers.try(&.visible = true)
        @compact_spacer.try(&.visible = false)
      else
        set_expanded_interface_visible(false)
      end

      set_library_panel_visible(@settings.show_library?)
      set_lyrics_panel_visible(@settings.show_lyrics?)
    end

    private def set_expanded_interface_visible(visible : Bool) : Nil
      window = @window

      if visible
        restore_expanded_interface_window_resize_limits
      elsif window && @settings.expanded_interface?
        save_expanded_layout_settings
        if width = @settings.expanded_window_width
          if height = @settings.expanded_window_height
            @expanded_interface_window_size = Qt6::Size.new(width, height)
          end
        end
      end

      @browsers.try(&.visible = visible)
      @compact_spacer.try(&.visible = !visible)

      if window
        window.adjust_size
        if visible
          if expanded_size = @expanded_interface_window_size
            window.resize(expanded_size.width, expanded_size.height)
            @last_expanded_window_size = expanded_size
            @expanded_interface_window_size = nil
          end
        elsif expanded_size = @expanded_interface_window_size
          window.resize(expanded_size.width, window.size.height)
        end
      end

      unless visible
        lock_minimal_window_height
      end

      action = @app_actions.try(&.expanded_interface)
      action.checked = visible if action && action.checked? != visible

      if @settings.expanded_interface? != visible
        @settings.expanded_interface = visible
        @settings.save
      end
    end

    private def set_blurred_cover_background_enabled(enabled : Bool) : Nil
      action = @app_actions.try(&.blurred_cover_background)
      action.checked = enabled if action && action.checked? != enabled

      if @settings.blurred_cover_background? != enabled
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
      action = @app_actions.try(&.expanded_interface)
      if action
        action.checked = !action.checked?
      else
        set_expanded_interface_visible(!@settings.expanded_interface?)
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
      @last_expanded_window_size = expanded_size
    end

    private def remember_expanded_window_size(window : Qt6::MainWindow) : Nil
      return unless @settings.expanded_interface?
      return if window.maximized?

      size = window.size
      return unless size.width.positive? && size.height.positive?

      @last_expanded_window_size = size
    end

    private def restore_library_queue_splitter_sizes(splitter : Qt6::Splitter) : Nil
      sizes = @settings.library_queue_splitter_sizes
      return unless sizes.size == 3 && sizes.all?(&.positive?)

      splitter.set_sizes(sizes)
    end

    private def save_expanded_layout_settings : Nil
      if @settings.expanded_interface?
        if window = @window
          maximized = window.maximized?
          size =
            if maximized
              @last_expanded_window_size || begin
                normal = window.normal_geometry
                Qt6::Size.new(normal.width, normal.height)
              end
            else
              window.size
            end
          @last_expanded_window_size = size unless maximized
          @settings.expanded_window_maximized = maximized
          @settings.expanded_window_width = size.width
          @settings.expanded_window_height = size.height
          @expanded_interface_window_size = size
        end

        if splitter = @browsers
          sizes = splitter.sizes
          @settings.library_queue_splitter_sizes = sizes if sizes.size == 3 && sizes.all?(&.>(0))
        end
      elsif expanded_size = @expanded_interface_window_size
        @settings.expanded_window_maximized = false
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

      action = @app_actions.try(&.show_library)
      action.checked = visible if action && action.checked? != visible

      if @settings.show_library? != visible
        @settings.show_library = visible
        @settings.save
      end
    end

    private def set_lyrics_panel_visible(visible : Bool) : Nil
      @lyrics_panel.try(&.visible = visible)

      action = @app_actions.try(&.show_lyrics)
      action.checked = visible if action && action.checked? != visible

      if @settings.show_lyrics? != visible
        @settings.show_lyrics = visible
        @settings.save
      end

      if visible
        apply_lyrics_settings
        sync_lyrics_position
      else
        @lyrics_service.cancel
      end
    end

    private def open_settings_dialog : Nil
      parent = @window
      return unless parent

      if SettingsDialog.edit(parent, @settings)
        setup_lastfm
        apply_visualizer_settings
        apply_lyrics_settings
        connect
      end
    end

    private def apply_visualizer_settings : Nil
      @visualizer_service.configure(
        @settings.visualizer_enabled?,
        @settings.visualizer_fifo_path
      )
      @player_header_view.try(&.visualizer.enabled = @settings.visualizer_enabled?)
    end

    private def quit_application : Nil
      shutdown_application
      @qt_app.quit
    end

    private def shutdown_application : Nil
      return if @quitting

      save_expanded_layout_settings
      @quitting = true
      @connection_generation.set(@connection_generation.get + 1)
      @callback_generation.set(@callback_generation.get + 1)
      @event_bridge.shutdown
      @visualizer_service.stop
      @client.try(&.disconnect)
      @callback_client.try(&.disconnect)
      @stored_playlist_idle_client.try(&.disconnect)
      @client = nil
      @callback_client = nil
      @stored_playlist_idle_client = nil
      @lastfm_adapter.try(&.stop)
      @mpris_adapter.try(&.stop)
      @tray_icon.try(&.hide)
    end

    private def reset_views : Nil
      return if @quitting
      return unless @mpd_available

      @mpd_available = false
      @client.try(&.disconnect)
      @client = nil
      @database_loaded = false
      @database_loading = false
      @library_index.replace([] of Song)
      @queue_controller.replace([] of Song)
      @visualizer_service.reset
      @queue_view.try(&.render([] of Song) { |_pos| "" })
      @playlists_view.try(&.render_message("Disconnected from MPD"))
      show_database_message("Disconnected from MPD")
      clear_outputs_menu("Disconnected")
      wait_for_status_after_reconnect
    end

    private def reload_views : Nil
      return if @quitting
      return if @mpd_available

      @client.try(&.disconnect)
      @client = MPD::Client.new(@settings.host, @settings.port)
      @mpd_available = true
      @waiting_for_mpd_status = false
      request_status_refresh
      refresh_outputs_menu
      ensure_database_loaded(force: true) if @library_view
      refresh_stored_playlists if @playlists_view
    rescue ex
      @client = nil
      @mpd_available = false
      Log.warn { "mpd_ui: failed to restore MPD client after reconnect: #{ex.message || ex}" }
      wait_for_status_after_reconnect
    end

    private def set_status(message : String) : Nil
      @status_bar.try(&.show_message(message))
    end
  end
end
