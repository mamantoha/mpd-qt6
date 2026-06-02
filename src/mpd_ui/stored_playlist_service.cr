module MPDUI
  class StoredPlaylistService
    def entries(client : MPD::Client) : Array(PlaylistEntry)
      client.listplaylists.try do |playlists|
        playlists.compact_map do |metadata|
          playlist_entry = PlaylistEntry.from_mpd(metadata)
          next unless playlist_entry

          songs = client.listplaylistinfo(playlist_entry.name).try(&.map { |song_metadata| Song.from_mpd(song_metadata) }) || [] of Song
          playlist_entry.build(songs)
        end.sort_by!(&.name.downcase)
      end || [] of PlaylistEntry
    end

    def save_queue(client : MPD::Client, name : String) : Nil
      mode = entries(client).any? { |playlist| playlist.name == name } ? "replace" : nil
      client.save(name, mode)
    end

    def load(client : MPD::Client, name : String, *, replace : Bool) : Nil
      client.clear if replace
      client.load(name)
    end

    def delete(client : MPD::Client, name : String) : Nil
      client.rm(name)
    end

    def rename(client : MPD::Client, old_name : String, new_name : String) : Nil
      client.rename(old_name, new_name)
    end

    def add_songs_to_queue(client : MPD::Client, uris : Array(String)) : Nil
      client.with_command_list do
        uris.each { |uri| client.add(uri) }
      end
    end

    def add_queue_songs_to_playlist(client : MPD::Client, name : String, uris : Array(String), position : Int32?) : Nil
      client.with_command_list do
        uris.each_with_index do |uri, offset|
          client.playlistadd(name, uri, position.try { |value| value + offset })
        end
      end
    end

    def remove_songs(client : MPD::Client, name : String, positions : Array(Int32)) : Nil
      client.with_command_list do
        positions.each { |position| client.playlistdelete(name, position) }
      end
    end

    def move_songs(client : MPD::Client, name : String, moves : Array(Tuple(Int32, Int32))) : Nil
      client.with_command_list do
        moves.each do |from, to|
          client.playlistmove(name, from, to)
        end
      end
    end
  end
end
