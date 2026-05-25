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
  end
end
