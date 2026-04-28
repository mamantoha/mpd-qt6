module MPDUI
  module FormatHelpers
    private def format_time(seconds : Float64) : String
      t = seconds.to_i
      "#{t // 60}:#{(t % 60).to_s.rjust(2, '0')}"
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

    private def display_name(value : String?, fallback : String) : String
      if value && !value.strip.empty?
        value
      else
        fallback
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

    private def song_tooltip(song : Hash(String, String)) : String
      file = song["file"]?
      title = song["Title"]? || (file ? File.basename(file, File.extname(file)) : "Unknown")
      duration = playlist_duration(song)

      rows = [] of Tuple(String, String)
      rows << {"Title", title}
      add_metadata_row(rows, "Artist", song["Artist"]?)
      add_metadata_row(rows, "Album", song["Album"]?)
      add_metadata_row(rows, "Track number", song["Track"]?.try(&.split('/').first))
      add_metadata_row(rows, "Disc number", song["Disc"]?.try(&.split('/').first))
      add_metadata_row(rows, "Genre", song["Genre"]?)
      add_metadata_row(rows, "Year", song["Date"]?)
      rows << {"Length", duration} unless duration.empty?

      String.build do |html|
        html << "<table cellspacing=\"3\">"
        rows.each do |label, value|
          html << "<tr><td align=\"right\"><b>"
          html << html_escape(label)
          html << ":</b></td><td>"
          html << html_escape(value)
          html << "</td></tr>"
        end
        html << "</table>"

        if file && !file.empty?
          html << "<div style=\"margin-top: 8px;\"><i>"
          html << html_escape(file)
          html << "</i></div>"
        end
      end
    end

    private def add_metadata_row(rows : Array(Tuple(String, String)), label : String, value : String?) : Nil
      return unless value && !value.strip.empty?

      rows << {label, value}
    end

    private def html_escape(value : String) : String
      value.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;").gsub('"', "&quot;")
    end
  end
end
