module MPDUI
  module AppDatabase
    private record DatabaseLoadResult,
      songs : Array(Song),
      genres : Array(String)

    private def build_database_browser(parent : Qt6::Widget) : Qt6::Widget
      library = LibraryView.new(parent)
      @database_filter_timer = Qt6::QTimer.new(parent).tap do |timer|
        timer.single_shot = true
        timer.interval = 180
        timer.on_timeout { apply_database_filter }
      end

      library.on_search_changed = -> { schedule_database_filter }
      library.on_search_closed = -> { hide_database_search }
      library.on_genre_changed = -> { apply_database_filter }
      library.on_add_to_queue = -> { add_selected_database_to_queue }
      library.on_selection_changed = -> {
        @drag_context.reset_selection
        library.clear_drag_uris
      }
      library.on_mouse_press = -> {
        @drag_context.begin_database_drag
        library.clear_drag_uris
      }
      library.on_drag_enter = -> { @drag_context.begin_database_drag }
      library.on_mouse_release = -> { @drag_context.finish_drag }
      library.on_drag_finished = -> { @drag_context.finish_drag }

      @library_view = library
      setup_database_drag_source(library)
      show_database_message("Open the Database tab to load your library")
      library.root
    end

    private def setup_database_drag_source(library : LibraryView) : Nil
      library.install_drag_filter
      @database_drag_filter = library.drag_filter
    end

    private def add_selected_database_to_queue : Nil
      append_selected_database_to_queue
    end

    private def show_database_search : Nil
      return unless @settings.expanded_interface?
      return unless @settings.show_library?

      preserve_window_size do
        set_library_panel_visible(true)
        @library_view.try(&.show_search)
      end
    end

    private def hide_database_search : Nil
      library = @library_view
      return unless library

      if library.search_empty?
        apply_database_filter
      else
        library.clear_search
      end

      preserve_window_size do
        library.hide_search
      end
    end

    private def preserve_window_size(& : ->) : Nil
      window = @window

      unless window
        yield
        return
      end

      size = window.size

      yield

      window.resize(size.width, size.height)
    end

    private def ensure_database_loaded(*, force : Bool = false, update_mpd : Bool = false) : Nil
      return if @database_loading
      return if @database_loaded && !force

      @database_loading = true
      show_database_message(update_mpd ? "Updating database…" : "Loading database…")
      set_status("#{update_mpd ? "Updating" : "Loading"} database from #{@settings.host}:#{@settings.port}…")

      host = @settings.host
      port = @settings.port

      run_background(
        ->(result : DatabaseLoadResult) {
          @library_index.replace(result.songs)
          @database_loaded = true
          @database_loading = false
          @library_view.try(&.render_genres(result.genres))
          apply_database_filter(force: true)
        },
        ->(ex : Exception) {
          @database_loaded = false
          @database_loading = false
          show_database_message("Failed to load database")
          set_status("Database load failed: #{ex.message || ex}")
        }
      ) do
        db_client = MPD::Client.new(host, port)
        if update_mpd
          db_client.update
          wait_for_mpd_database_update(db_client)
        end
        songs = LibraryIndex.from_mpd_entries(db_client.listallinfo)
        genres = (db_client.list("Genre") || [] of String).map(&.strip).reject(&.empty?).uniq!.sort!
        genres << "Unknown" if songs.any? { |song| song.genre.nil? }
        DatabaseLoadResult.new(songs, genres.uniq!.sort!)
      ensure
        db_client.try(&.disconnect)
      end
    end

    private def wait_for_mpd_database_update(client : MPD::Client) : Nil
      600.times do
        status = client.status
        break unless status && status["updating_db"]?

        sleep 200.milliseconds
      end
    end

    private def show_database_message(message : String) : Nil
      @library_view.try(&.show_message(message))
    end

    private def apply_database_filter : Nil
      apply_database_filter(force: false)
    end

    private def apply_database_filter(*, force : Bool) : Nil
      library = @library_view
      unless library
        return
      end

      query = library.as(LibraryView).query
      genre = library.as(LibraryView).selected_genre
      return if !force && query == @last_database_filter_query && genre == @last_database_filter_genre

      @database_filter_timer.try(&.stop)
      @last_database_filter_query = query
      @last_database_filter_genre = genre

      songs = @library_index.songs.dup
      generation = @database_filter_generation.add(1) + 1

      run_background(
        ->(result : LibraryIndex::Result) {
          if @database_filter_generation.get == generation
            library = @library_view

            if library && library.as(LibraryView).query == query && library.as(LibraryView).selected_genre == genre
              library.as(LibraryView).render(result, expand_all: !query.empty?)

              if result.filtered
                set_status("Database filter: #{result.songs_count} of #{songs.size} songs")
              else
                set_status("Database loaded • #{songs.size} songs") if @database_loaded
              end
            end
          end
        },
        ->(ex : Exception) {
          if @database_filter_generation.get == generation
            show_database_message("Failed to filter database")
            set_status("Database filter failed: #{ex.message || ex}")
          end
        }
      ) do
        LibraryIndex.new(songs).filter(query, genre)
      end
    end

    private def schedule_database_filter : Nil
      @database_filter_timer.try(&.start)
    end

    private def selected_database_uris : Array(String)
      @library_view.try(&.selected_uris) || [] of String
    end

    private def queue_source_uris : Array(String)
      if @drag_context.stored_playlist?
        selected_stored_playlist_song_uris
      elsif @drag_context.database?
        drag_uris = @library_view.try(&.drag_uris) || [] of String
        drag_uris.empty? ? selected_database_uris : drag_uris.dup
      else
        selected_database_uris
      end
    end

    private def append_selected_database_to_queue(insert_row : Int32? = nil) : Bool
      uris = queue_source_uris
      return false if uris.empty?

      base_position = @queue_controller.base_position_for_insert(insert_row)
      host = @settings.host
      port = @settings.port
      suffix = uris.size == 1 ? "song" : "songs"
      action = insert_row ? "Inserting" : "Adding"
      set_status("#{action} #{uris.size} #{suffix} from Database…")

      run_background(
        ->(_result : Nil) {
          done_action = insert_row ? "Inserted" : "Added"
          set_status("#{done_action} #{uris.size} #{suffix} from Database")
        },
        ->(ex : Exception) {
          @title_label.try(&.text = "Error")
          @subtitle_label.try(&.text = (ex.message || ex.to_s))
          set_status("Failed to add songs from Database")
        }
      ) do
        with_mpd_client(host, port) do |client|
          client.with_command_list do
            if base_position
              uris.each_with_index do |uri, offset|
                client.addid(uri, base_position + offset)
              end
            else
              uris.each { |uri| client.add(uri) }
            end
          end
        end
        nil
      end

      true
    end
  end
end
