module MPDUI
  module AppTray
    private def setup_system_tray(window : Qt6::MainWindow) : Nil
      return unless Qt6::SystemTrayIcon.system_tray_available?

      tray = Qt6::SystemTrayIcon.new(window)
      tray_icon = Qt6::QIcon.from_theme("audio-x-generic")
      tray_icon = @play_icon.not_nil! if tray_icon.null? && @play_icon
      tray.icon = tray_icon unless tray_icon.null?
      tray.tool_tip = App::WINDOW_TITLE

      menu = Qt6::Menu.new("Tray", window)
      toggle_action = Qt6::Action.new("Hide", window)
      show_icon = Qt6::QIcon.from_theme("window")
      toggle_action.icon = show_icon unless show_icon.null?
      toggle_action.on_triggered { toggle_main_window_visibility }
      menu.add_action(toggle_action)
      menu.add_separator

      previous_action = Qt6::Action.new("Previous", window)
      previous_icon = Qt6::QIcon.from_theme("media-skip-backward")
      previous_action.icon = previous_icon unless previous_icon.null?
      previous_action.on_triggered { mpd_action { |c| c.previous } }
      menu.add_action(previous_action)

      play_pause_action = Qt6::Action.new("Play/Pause", window)
      play_pause_action.icon = @play_icon.not_nil! if @play_icon && !@play_icon.not_nil!.null?
      play_pause_action.on_triggered { toggle_play_pause }
      menu.add_action(play_pause_action)

      next_action = Qt6::Action.new("Next", window)
      next_icon = Qt6::QIcon.from_theme("media-skip-forward")
      next_action.icon = next_icon unless next_icon.null?
      next_action.on_triggered { mpd_action { |c| c.next } }
      menu.add_action(next_action)

      menu.add_separator

      quit_action = Qt6::Action.new("Quit", window)
      quit_icon = Qt6::QIcon.from_theme("application-exit")
      quit_action.icon = quit_icon unless quit_icon.null?
      quit_action.on_triggered { quit_application }
      menu.add_action(quit_action)

      tray.context_menu = menu
      tray.on_activated do |reason|
        case reason
        when .trigger?, .double_click?
          toggle_main_window_visibility
        end
      end
      tray.on_message_clicked { show_main_window }
      tray.show

      @tray_icon = tray
      @tray_menu = menu
      @toggle_window_action = toggle_action
      install_window_tray_filter(window)
      sync_tray_state
    end

    private def install_window_tray_filter(window : Qt6::MainWindow) : Nil
      filter = Qt6::EventFilter.new(window)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::Close
          if @quitting || !@tray_icon
            false
          else
            event.ignore
            hide_main_window_to_tray
            true
          end
        when Qt6::EventType::Hide
          sync_tray_state
          false
        when Qt6::EventType::Show
          sync_tray_state
          @qt_app.invoke_later { scroll_playlist_to_current_song }
          false
        else
          false
        end
      end

      window.install_event_filter(filter)
      @window_event_filter = filter
    end

    private def toggle_main_window_visibility : Nil
      window = @window
      return unless window

      if window.visible?
        hide_main_window_to_tray
      else
        show_main_window
      end
    end

    private def hide_main_window_to_tray : Nil
      @window.try(&.hide)
      maybe_show_tray_message
      sync_tray_state
    end

    private def show_main_window : Nil
      window = @window
      return unless window

      window.show
      window.raise_to_front
      window.set_focus
      @tray_message_shown = false
      sync_tray_state
      @qt_app.invoke_later { scroll_playlist_to_current_song }
    end

    private def maybe_show_tray_message : Nil
      tray = @tray_icon
      return unless tray
      return if @tray_message_shown
      return unless tray.supports_messages?

      tray.show_message(App::WINDOW_TITLE, "The app is still running in the system tray.", timeout: 2500)
      @tray_message_shown = true
    end

    private def sync_tray_state : Nil
      action = @toggle_window_action
      return unless action

      action.text = @window.try(&.visible?) ? "Hide" : "Show"
      icon_name = @window.try(&.visible?) ? "window-close" : "window"
      icon = Qt6::QIcon.from_theme(icon_name)
      action.icon = icon unless icon.null?
    end

    private def update_tray_tooltip(title : String, subtitle : String = "") : Nil
      tray = @tray_icon
      return unless tray

      tooltip = subtitle.empty? ? "#{App::WINDOW_TITLE}\n#{title}" : "#{App::WINDOW_TITLE}\n#{title}\n#{subtitle}"
      tray.tool_tip = tooltip
    end

    private def quit_application : Nil
      @quitting = true
      @mpris_service.try(&.stop)
      @tray_icon.try(&.hide)
      @qt_app.quit
    end
  end
end
