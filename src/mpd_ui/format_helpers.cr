module MPDUI
  module FormatHelpers
    private def format_time(seconds : Float64) : String
      Song.format_time(seconds)
    end

    private def format_stats_duration(raw_seconds : String?) : String
      seconds = raw_seconds.try(&.to_i64?) || return "Unknown"
      return "0s" if seconds <= 0

      parts = [] of String
      days = seconds // 86_400
      hours = (seconds % 86_400) // 3_600
      minutes = (seconds % 3_600) // 60
      secs = seconds % 60

      parts << "#{days}d" if days.positive?
      parts << "#{hours}h" if hours.positive?
      parts << "#{minutes}m" if minutes.positive?
      parts << "#{secs}s" if secs.positive? || parts.empty?
      parts.join(' ')
    end

    private def format_stats_timestamp(raw_timestamp : String?) : String
      timestamp = raw_timestamp.try(&.to_i64?) || return "Unknown"
      Time.unix(timestamp).to_local.to_s("%Y-%m-%d %H:%M:%S %Z")
    rescue
      "Unknown"
    end

    private def playlist_title(song : Song) : String
      song.queue_title
    end

    private def playlist_duration(song : Song) : String
      song.duration_label
    end

    private def database_song_label(song : Song) : String
      song.database_label
    end

    private def track_number(song : Song) : Int32
      song.track_number || Int32::MAX
    end

    private def disc_number(song : Song) : Int32
      song.disc_number || Int32::MAX
    end

    private def song_tooltip(song : Song) : String
      song.tooltip_html
    end
  end
end
