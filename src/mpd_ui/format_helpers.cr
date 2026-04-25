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
  end
end
