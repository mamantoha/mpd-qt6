module MPDUI
  class Song
    getter metadata : Hash(String, String)

    def self.from_mpd(metadata : Hash(String, String)) : self
      new(metadata)
    end

    def initialize(@metadata : Hash(String, String))
    end

    def file : String?
      value("file")
    end

    def pos : Int32?
      value("Pos").try(&.to_i?)
    end

    def id : Int32?
      value("Id").try(&.to_i?)
    end

    def title : String?
      value("Title")
    end

    def artist : String?
      value("Artist")
    end

    def album : String?
      value("Album")
    end

    def album_artist : String?
      value("AlbumArtist")
    end

    def subtitle : String
      [artist, album].compact.join(" • ")
    end

    def genre : String?
      value("Genre")
    end

    def date : String?
      value("Date") || value("OriginalDate") || value("Year")
    end

    def duration : Float64?
      value("Time").try(&.to_f?) || value("duration").try(&.to_f?)
    end

    def track_number : Int32?
      metadata_number("Track")
    end

    def disc_number : Int32?
      metadata_number("Disc", "DiscNumber", "Discnumber")
    end

    def display_title : String
      title || file_base_name || "Unknown"
    end

    def queue_title : String
      text = [artist, display_title].compact.join(" — ")
      text.empty? ? display_title : text
    end

    def duration_label : String
      seconds = duration
      seconds ? self.class.format_time(seconds) : ""
    end

    def database_label : String
      base =
        if track = raw_track_number
          "#{track.rjust(2, '0')}. #{display_title}"
        else
          display_title
        end

      duration_label.empty? ? base : "#{base} • #{duration_label}"
    end

    def tooltip_html : String
      rows = [] of Tuple(String, String)
      rows << {"Title", display_title}
      add_metadata_row(rows, "Artist", artist)
      add_metadata_row(rows, "Album", album)
      add_metadata_row(rows, "Track number", raw_track_number)
      add_metadata_row(rows, "Disc number", raw_disc_number)
      add_metadata_row(rows, "Genre", genre)
      add_metadata_row(rows, "Year", date)
      rows << {"Length", duration_label} unless duration_label.empty?

      String.build do |html|
        html << "<table cellspacing=\"3\">"
        rows.each do |label, value|
          html << "<tr><td align=\"right\"><b>"
          html << self.class.html_escape(label)
          html << ":</b></td><td>"
          html << self.class.html_escape(value)
          html << "</td></tr>"
        end
        html << "</table>"

        if path = file
          unless path.empty?
            html << "<div style=\"margin-top: 8px;\"><i>"
            html << self.class.html_escape(path)
            html << "</i></div>"
          end
        end
      end
    end

    def year : Int32?
      date.try do |value|
        value.match(/\d{4}/).try { |match| match[0].to_i? }
      end
    end

    def self.format_time(seconds : Float64) : String
      t = seconds.to_i
      "#{t // 60}:#{(t % 60).to_s.rjust(2, '0')}"
    end

    def self.html_escape(value : String) : String
      value.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;").gsub('"', "&quot;")
    end

    private def value(key : String) : String?
      metadata[key]?.try(&.strip).try { |value| value.empty? ? nil : value }
    end

    private def file_base_name : String?
      file.try { |path| File.basename(path, File.extname(path)) }
    end

    private def raw_track_number : String?
      value("Track").try(&.split('/').first.strip)
    end

    private def raw_disc_number : String?
      value("Disc").try(&.split('/').first.strip)
    end

    private def metadata_number(*keys : String) : Int32?
      keys.each do |key|
        value = value(key)
        next unless value

        part = value.split('/').first.strip
        if number = part.to_i?
          return number
        end

        if match = part.match(/\d+/)
          return match[0].to_i
        end
      end

      nil
    end

    private def add_metadata_row(rows : Array(Tuple(String, String)), label : String, value : String?) : Nil
      return unless value && !value.strip.empty?

      rows << {label, value}
    end
  end
end
