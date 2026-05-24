module MPDUI
  module AppWindowEvents
    private def install_window_event_filter(window : Qt6::MainWindow) : Nil
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
        when Qt6::EventType::Resize
          remember_expanded_window_size(window) unless @quitting
          false
        else
          false
        end
      end

      window.install_event_filter(filter)
      @window_event_filter = filter
    end
  end
end
