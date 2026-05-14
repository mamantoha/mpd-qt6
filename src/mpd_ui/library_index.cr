module MPDUI
  class LibraryIndex
    UNKNOWN_ARTIST = "[Unknown Artist]"
    UNKNOWN_ALBUM  = "[Unknown Album]"

    getter songs : Array(Song)

    record AlbumEntry,
      title : String,
      songs : Array(Song) do
      def summary : String
        duration = songs.sum { |song| song.duration || 0.0 }
        "#{songs.size} #{songs.size == 1 ? "Track" : "Tracks"}#{duration.positive? ? " (#{Song.format_time(duration)})" : ""}"
      end
    end

    record ArtistEntry,
      name : String,
      albums : Array(AlbumEntry) do
      def summary : String
        "#{albums.size} #{albums.size == 1 ? "Album" : "Albums"}"
      end
    end

    record Result,
      artists : Array(ArtistEntry),
      songs_count : Int32,
      filtered : Bool

    def self.from_mpd_entries(entries : MPD::Object | MPD::Objects?) : Array(Song)
      return [] of Song unless entries

      case entries
      when Array
        entries.select { |entry| !!entry["file"]? }.map { |entry| Song.from_mpd(entry) }
      else
        entries["file"]? ? [Song.from_mpd(entries)] : [] of Song
      end
    end

    def initialize(@songs : Array(Song) = [] of Song)
    end

    def replace(songs : Array(Song)) : Nil
      @songs = songs
    end

    def filter(query : String) : Result
      terms = query.downcase.split.reject(&.empty?)
      filtered_songs = terms.empty? ? @songs : @songs.select { |song| matches?(song, terms) }
      Result.new(group(filtered_songs), filtered_songs.size, !terms.empty?)
    end

    private def group(songs : Array(Song)) : Array(ArtistEntry)
      library = Hash(String, Hash(String, Array(Song))).new do |artists, artist|
        artists[artist] = Hash(String, Array(Song)).new do |albums, album|
          albums[album] = [] of Song
        end
      end

      songs.each do |song|
        artist = display_name(song.artist, UNKNOWN_ARTIST)
        album = display_name(song.album, UNKNOWN_ALBUM)
        library[artist][album] << song
      end

      library.keys.sort!.map do |artist|
        albums = library[artist]
        album_entries = albums.keys.sort_by! { |album| album_sort_key(album, albums[album]) }.map do |album|
          AlbumEntry.new(album, albums[album].sort_by { |song| song_sort_key(song) })
        end
        ArtistEntry.new(artist, album_entries)
      end
    end

    private def matches?(song : Song, terms : Array(String)) : Bool
      haystack = [
        song.artist,
        song.album,
        song.title,
        song.file,
      ].compact.join(" ").downcase

      terms.all? { |term| haystack.includes?(term) }
    end

    private def album_sort_key(album : String, songs : Array(Song)) : Tuple(Int32, String)
      {album_year(songs), album.downcase}
    end

    private def album_year(songs : Array(Song)) : Int32
      years = songs.compact_map(&.year)
      years.min? || Int32::MAX
    end

    private def song_sort_key(song : Song) : Tuple(Int32, Int32, String)
      {song.disc_number || Int32::MAX, song.track_number || Int32::MAX, song.database_label.downcase}
    end

    private def display_name(value : String?, fallback : String) : String
      if value && !value.strip.empty?
        value
      else
        fallback
      end
    end
  end
end
