module MPDUI
  module AppPlaylists
    private def build_playlists(parent : Qt6::Widget) : PlaylistsView
      playlists = PlaylistsView.new(parent)
      playlists.on_refresh = -> { refresh_stored_playlists }
      playlists.on_replace_queue = -> { load_selected_stored_playlist(replace: true) }
      playlists.on_add_to_queue = -> { load_selected_stored_playlist(replace: false) }
      playlists.on_rename = -> { rename_selected_stored_playlist }
      playlists.on_delete = -> { delete_selected_stored_playlist }
      playlists.on_add_songs_to_queue = -> { add_selected_stored_playlist_songs_to_queue }
      playlists.on_remove_songs = -> { remove_selected_stored_playlist_songs }
      playlists.on_move_songs = ->(name : String, moves : Array(Tuple(Int32, Int32))) { move_stored_playlist_songs(name, moves) }
      playlists.on_song_selection_changed = -> { @dragged_database_uris = selected_stored_playlist_song_uris }
      playlists.on_song_mouse_press = -> {
        @playlist_drag_source_row = nil
        @dragged_database_uris.clear
        @drag_source_type = :stored_playlist
      }
      playlists.on_song_drag_enter = -> { @drag_source_type = :stored_playlist }
      playlists.on_song_drag_finished = -> { @drag_source_type = nil }
      playlists.render_message("No playlist selected")
      @playlists_view = playlists
      playlists
    end

    private def save_queue_as_playlist : Nil
      queue = @queue_view
      return unless queue

      if queue.empty?
        show_playlist_message("Save Playlist", "The queue is empty.")
        return
      end

      name = Qt6::InputDialog.get_text(@window, title: "Save Playlist", label: "Playlist name:")
      return unless name

      playlist_name = name.strip
      return if playlist_name.empty?

      set_status("Saving playlist #{playlist_name}…")
      host = @settings.host
      port = @settings.port

      run_background(
        ->(_result : Nil) {
          set_status("Saved playlist #{playlist_name}")
        },
        ->(ex : Exception) {
          show_playlist_message("Save Playlist Failed", ex.message || ex.to_s)
          set_status("Failed to save playlist #{playlist_name}")
        }
      ) do
        with_playlist_client(host, port) do |client|
          existing = playlist_entries(client)
          mode = existing.any? { |playlist| playlist.name == playlist_name } ? "replace" : nil
          client.save(playlist_name, mode)
        end
      end
    end

    private def refresh_stored_playlists : Nil
      set_status("Loading stored playlists…")
      host = @settings.host
      port = @settings.port

      run_background(
        ->(playlists : Array(PlaylistEntry)) {
          @playlists_view.try(&.render_playlists(playlists))
          set_status("#{playlists.size} stored #{playlists.size == 1 ? "playlist" : "playlists"}")
        },
        ->(ex : Exception) {
          @playlists_view.try(&.render_message("Failed to load playlists"))
          set_status("Failed to load playlists: #{ex.message || ex}")
        }
      ) do
        with_playlist_client(host, port) { |client| playlist_entries(client) }
      end
    end

    private def load_selected_stored_playlist(*, replace : Bool) : Nil
      name = @playlists_view.try(&.selected_playlist_name)
      return unless name

      set_status("#{replace ? "Replacing Queue with" : "Adding"} playlist #{name}…")
      host = @settings.host
      port = @settings.port

      run_background(
        ->(_result : Nil) {
          set_status("#{replace ? "Replaced Queue with" : "Added"} playlist #{name}")
        },
        ->(ex : Exception) {
          show_playlist_message("Load Playlist Failed", ex.message || ex.to_s)
          set_status("Failed to load playlist #{name}")
        }
      ) do
        with_playlist_client(host, port) do |client|
          client.clear if replace
          client.load(name)
        end
      end
    end

    private def delete_selected_stored_playlist : Nil
      name = @playlists_view.try(&.selected_playlist_name)
      return unless name

      return unless confirm_delete_playlist(name)

      set_status("Deleting playlist #{name}…")
      host = @settings.host
      port = @settings.port

      run_background(
        ->(_result : Nil) {
          set_status("Deleted playlist #{name}")
        },
        ->(ex : Exception) {
          show_playlist_message("Delete Playlist Failed", ex.message || ex.to_s)
          set_status("Failed to delete playlist #{name}")
        }
      ) do
        with_playlist_client(host, port) do |client|
          client.rm(name)
        end
      end
    end

    private def rename_selected_stored_playlist : Nil
      old_name = @playlists_view.try(&.selected_playlist_name)
      return unless old_name

      name = Qt6::InputDialog.get_text(@window, title: "Rename Playlist", label: "Playlist name:", value: old_name)
      return unless name

      new_name = name.strip
      return if new_name.empty? || new_name == old_name

      set_status("Renaming playlist #{old_name}…")
      host = @settings.host
      port = @settings.port

      run_background(
        ->(_result : Nil) {
          set_status("Renamed playlist #{old_name} to #{new_name}")
        },
        ->(ex : Exception) {
          show_playlist_message("Rename Playlist Failed", ex.message || ex.to_s)
          set_status("Failed to rename playlist #{old_name}")
        }
      ) do
        with_playlist_client(host, port) do |client|
          client.rename(old_name, new_name)
        end
      end
    end

    private def playlist_entries(client : MPD::Client) : Array(PlaylistEntry)
      client.listplaylists.try do |playlists|
        playlists.compact_map do |metadata|
          playlist_entry = PlaylistEntry.from_mpd(metadata)
          next unless playlist_entry

          songs = client.listplaylistinfo(playlist_entry.name).try(&.map { |song_metadata| Song.from_mpd(song_metadata) }) || [] of Song
          playlist_entry.build(songs)
        end.sort_by!(&.name.downcase)
      end || [] of PlaylistEntry
    end

    private def selected_stored_playlist_song_uris : Array(String)
      @playlists_view.try(&.selected_song_uris) || [] of String
    end

    private def add_selected_stored_playlist_songs_to_queue : Nil
      uris = selected_stored_playlist_song_uris
      return if uris.empty?

      set_status("Adding #{uris.size} #{uris.size == 1 ? "song" : "songs"} to queue…")
      host = @settings.host
      port = @settings.port

      run_background(
        ->(_result : Nil) {
          set_status("Added #{uris.size} #{uris.size == 1 ? "song" : "songs"} to queue")
        },
        ->(ex : Exception) {
          show_playlist_message("Add Songs Failed", ex.message || ex.to_s)
          set_status("Failed to add songs to queue")
        }
      ) do
        with_playlist_client(host, port) do |client|
          client.with_command_list do
            uris.each { |uri| client.add(uri) }
          end
        end
      end
    end

    private def remove_selected_stored_playlist_songs : Nil
      view = @playlists_view
      return unless view

      name = view.selected_playlist_name
      return unless name

      positions = view.selected_song_positions.sort.reverse!
      return if positions.empty?

      set_status("Removing #{positions.size} #{positions.size == 1 ? "song" : "songs"} from playlist #{name}…")
      host = @settings.host
      port = @settings.port

      run_background(
        ->(_result : Nil) {
          set_status("Removed #{positions.size} #{positions.size == 1 ? "song" : "songs"} from playlist #{name}")
        },
        ->(ex : Exception) {
          show_playlist_message("Remove Songs Failed", ex.message || ex.to_s)
          set_status("Failed to remove songs from playlist #{name}")
        }
      ) do
        with_playlist_client(host, port) do |client|
          client.with_command_list do
            positions.each { |position| client.playlistdelete(name, position) }
          end
        end
      end
    end

    private def move_stored_playlist_songs(name : String, moves : Array(Tuple(Int32, Int32))) : Nil
      moves = moves.reject { |from, to| from == to }
      return if moves.empty?

      set_status("Moving songs in playlist #{name}…")
      host = @settings.host
      port = @settings.port

      run_background(
        ->(_result : Nil) {
          set_status("Moved songs in playlist #{name}")
        },
        ->(ex : Exception) {
          show_playlist_message("Move Song Failed", ex.message || ex.to_s)
          set_status("Failed to move songs in playlist #{name}")
        }
      ) do
        with_playlist_client(host, port) do |client|
          client.with_command_list do
            moves.each do |from, to|
              client.playlistmove(name, from, to)
            end
          end
        end
      end
    end

    private def confirm_delete_playlist(name : String) : Bool
      dialog = Qt6::Dialog.new(@window)
      dialog.window_title = "Delete Playlist"

      label = Qt6::Label.new("Delete playlist #{name}?", dialog)
      buttons = Qt6::DialogButtonBox.new(
        Qt6::DialogButtonBoxStandardButton::Ok | Qt6::DialogButtonBoxStandardButton::Cancel,
        dialog
      )
      buttons.button(Qt6::DialogButtonBoxStandardButton::Ok).try(&.text = "Delete")
      buttons.on_accepted { dialog.accept }
      buttons.on_rejected { dialog.reject }

      dialog.vbox do |column|
        column.spacing = 10
        column.set_contents_margins(12, 12, 12, 12)
        column << label
        column << buttons
      end

      begin
        dialog.exec == Qt6::DialogCode::Accepted
      ensure
        dialog.release
      end
    end

    private def show_playlist_message(title : String, text : String) : Nil
      dialog = Qt6::Dialog.new(@window)
      dialog.window_title = title

      label = Qt6::Label.new(text, dialog)
      label.word_wrap = true
      label.minimum_width = 320

      buttons = Qt6::DialogButtonBox.new(Qt6::DialogButtonBoxStandardButton::Ok, dialog)
      buttons.on_accepted { dialog.accept }
      buttons.on_rejected { dialog.reject }

      dialog.vbox do |column|
        column.spacing = 10
        column.set_contents_margins(12, 12, 12, 12)
        column << label
        column << buttons
      end

      begin
        dialog.exec
      ensure
        dialog.release
      end
    end

    private def with_playlist_client(host : String, port : Int32, & : MPD::Client -> T) : T forall T
      client = MPD::Client.new(host, port)
      yield client
    ensure
      client.try(&.disconnect)
    end
  end
end
