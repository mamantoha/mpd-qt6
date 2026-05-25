module MPDUI
  module AppTray
    private def setup_system_tray(window : Qt6::MainWindow) : Nil
      return unless Qt6::SystemTrayIcon.system_tray_available?

      tray = Qt6::SystemTrayIcon.new(window)

      tray_icon = Qt6::QIcon.from_theme("audio-x-generic")
      tray_icon = @play_icon.not_nil! if tray_icon.null? && @play_icon
      tray.icon = tray_icon unless tray_icon.null?
      tray.tool_tip = App::WINDOW_TITLE

      toggle_action = Qt6::Action.new("Hide", window).tap do |action|
        icon = Qt6::QIcon.from_theme("window")
        action.icon = icon unless icon.null?
        action.on_triggered { toggle_main_window_visibility }
      end

      previous_action = Qt6::Action.new("Previous", window).tap do |action|
        icon = Qt6::QIcon.from_theme("media-skip-backward")
        action.icon = icon unless icon.null?
        action.on_triggered { mpd_action(&.previous) }
      end

      play_pause_action = Qt6::Action.new("Play/Pause", window).tap do |action|
        icon = Qt6::QIcon.from_theme("media-playback-start")
        action.icon = icon unless icon.null?
        action.on_triggered { toggle_play_pause }
      end

      next_action = Qt6::Action.new("Next", window).tap do |action|
        icon = Qt6::QIcon.from_theme("media-skip-forward")
        action.icon = icon unless icon.null?
        action.on_triggered { mpd_action(&.next) }
      end

      quit_action = Qt6::Action.new("Quit", window).tap do |action|
        icon = Qt6::QIcon.from_theme("application-exit")
        action.icon = icon unless icon.null?
        action.on_triggered { quit_application }
      end

      tray_menu = Qt6::Menu.new("Tray", window).tap do |menu|
        menu.add_action(toggle_action)
        menu.add_separator
        menu.add_action(previous_action)
        menu.add_action(play_pause_action)
        menu.add_action(next_action)
        menu.add_separator
        menu.add_action(quit_action)
      end

      tray.context_menu = tray_menu

      tray.on_activated do |reason|
        case reason
        when .trigger?, .double_click?
          toggle_main_window_visibility
        end
      end

      tray.on_message_clicked { show_main_window }

      tray.show

      @tray_icon = tray
      @tray_menu = tray_menu
      @toggle_window_action = toggle_action
      sync_tray_state
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
      return if @tray_message_shown

      show_tray_message("The app is still running in the system tray.")
      @tray_message_shown = true
    end

    private def show_tray_message(message : String, title : String = App::WINDOW_TITLE) : Nil
      tray = @tray_icon
      return unless tray
      return unless tray.supports_messages?

      tray.show_message(title, message, timeout: 2500)
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
  end
end
