module MPDUI
  class PlaylistEntry
    getter name : String
    getter last_modified : String?
    getter songs : Array(Song)

    def self.from_mpd(metadata : Hash(String, String)) : self?
      name = metadata["playlist"]?.try(&.strip)
      return if name.nil? || name.empty?

      new(name, metadata["Last-Modified"]?)
    end

    def build(songs : Array(Song)) : self
      PlaylistEntry.new(name, last_modified, songs)
    end

    def initialize(@name : String, @last_modified : String?, @songs : Array(Song) = [] of Song)
    end

    def summary : String?
      return if songs.empty?

      count = songs.size
      seconds = songs.compact_map(&.duration).sum
      "#{count} #{count == 1 ? "Track" : "Tracks"} (#{Song.format_time(seconds)})"
    end

    def tooltip : String
      if value = last_modified
        value.empty? ? name : "Last modified: #{value}"
      else
        name
      end
    end
  end
end
