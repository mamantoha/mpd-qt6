module MPDUI
  module AppAboutDialog
    private def open_about_dialog : Nil
      parent = @window
      return unless parent

      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = "About #{App::WINDOW_TITLE}"
      dialog.resize(520, 420)

      title_label = Qt6::Label.new("#{App::WINDOW_TITLE} #{MPDUI::VERSION}", dialog)
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
  end
end
