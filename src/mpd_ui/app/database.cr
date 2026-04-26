module MPDUI
  module AppDatabase
    private def build_database_browser(parent : Qt6::Widget) : Qt6::Widget
      container = Qt6::Widget.new(parent)
      tree = Qt6::TreeView.new(container)
      model = Qt6::StandardItemModel.new(tree)

      model.set_horizontal_header_label(0, "Database")
      tree.model = model
      tree.header_hidden = true
      tree.root_is_decorated = true
      tree.uniform_row_heights = true
      tree.selection_mode = Qt6::ItemSelectionMode::SingleSelection
      tree.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      tree.alternating_row_colors = true
      tree.drag_enabled = true
      tree.drag_drop_mode = Qt6::ItemViewDragDropMode::DragOnly
      tree.default_drop_action = Qt6::DropAction::CopyAction
      tree.drop_indicator_shown = true
      tree.minimum_height = 320

      tree.style_sheet = <<-CSS
        QTreeView {
          border: 1px solid;
        }
        QTreeView::item {
          padding: 4px 6px;
        }
      CSS

      tree.on_current_index_changed do
        @playlist_drag_source_row = nil
        @dragged_database_uris = selected_database_uris
      end

      container.vbox do |column|
        column << tree
      end

      @database_tree = tree
      @database_model = model
      setup_database_drag_source(tree)
      show_database_message("Open the Database tab to load your library")
      container
    end

    private def setup_database_drag_source(tree : Qt6::TreeView) : Nil
      viewport = tree.viewport
      filter = Qt6::EventFilter.new(viewport)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          @playlist_drag_source_row = nil
          @drag_source_type = :database
        when Qt6::EventType::DragEnter
          @drag_source_type = :database
        when Qt6::EventType::DragLeave, Qt6::EventType::Drop
          @drag_source_type = nil
        end
        false
      end

      viewport.install_event_filter(filter)
      @database_drag_filter = filter
    end

    private def ensure_database_loaded(*, force : Bool = false) : Nil
      return if @database_loading
      return if @database_loaded && !force

      @database_loading = true
      show_database_message("Loading database…")
      set_status("Loading database from #{@settings.host}:#{@settings.port}…")

      host = @settings.host
      port = @settings.port

      Thread.new do
        begin
          db_client = MPD::Client.new(host, port)
          raw_entries = db_client.listallinfo
          songs = database_song_entries(raw_entries)
          library = build_database_library(songs)
          db_client.disconnect

          @qt_app.invoke_later do
            populate_database_tree(library)
            @database_loaded = true
            @database_loading = false
            set_status("Database loaded • #{songs.size} songs")
          end
        rescue ex
          @qt_app.invoke_later do
            @database_loaded = false
            @database_loading = false
            show_database_message("Failed to load database")
            set_status("Database load failed: #{ex.message || ex}")
          end
        end
      end
    end

    private def show_database_message(message : String) : Nil
      model = @database_model
      return unless model

      model.clear
      model.set_horizontal_header_label(0, "Database")
      model << Qt6::StandardItem.new(message)
    end

    private def database_song_entries(entries : MPD::Object | MPD::Objects | Nil) : Array(Hash(String, String))
      return [] of Hash(String, String) unless entries

      case entries
      when Array
        entries.select { |entry| !!entry["file"]? }
      else
        entries["file"]? ? [entries] : [] of Hash(String, String)
      end
    end

    private def build_database_library(songs : Array(Hash(String, String))) : Hash(String, Hash(String, Array(Hash(String, String))))
      library = Hash(String, Hash(String, Array(Hash(String, String)))).new do |artists, artist|
        artists[artist] = Hash(String, Array(Hash(String, String))).new do |albums, album|
          albums[album] = [] of Hash(String, String)
        end
      end

      songs.each do |song|
        artist = display_name(song["Artist"]?, "[Unknown Artist]")
        album = display_name(song["Album"]?, "[Unknown Album]")
        library[artist][album] << song
      end

      library
    end

    private def populate_database_tree(library : Hash(String, Hash(String, Array(Hash(String, String))))) : Nil
      model = @database_model
      return unless model

      model.clear
      model.set_horizontal_header_label(0, "Database")

      if library.empty?
        model << Qt6::StandardItem.new("Database is empty")
        return
      end

      artist_icon = themed_icon("avatar-default", "user-identity", "system-users", "contact-new")
      album_icon = Qt6::QIcon.from_theme("media-optical-audio")
      song_icon = Qt6::QIcon.from_theme("audio-x-generic")

      library.keys.sort.each do |artist|
        artist_item = Qt6::StandardItem.new(artist)
        artist_item.icon = artist_icon unless artist_icon.null?

        library[artist].keys.sort.each do |album|
          album_songs = library[artist][album]
          album_item = Qt6::StandardItem.new("#{album} (#{album_songs.size})")
          album_item.icon = album_icon unless album_icon.null?

          album_songs.sort_by { |song| {track_number(song), database_song_label(song).downcase} }.each do |song|
            song_item = Qt6::StandardItem.new(database_song_label(song))
            song_item.icon = song_icon unless song_icon.null?
            if file = song["file"]?
              song_item.set_data(file, Qt6::ItemDataRole::User)
            end
            album_item << song_item
          end

          artist_item << album_item
        end

        model << artist_item
      end
    end

    private def themed_icon(*names : String) : Qt6::QIcon
      names.each do |name|
        icon = Qt6::QIcon.from_theme(name)
        return icon unless icon.null?
      end

      Qt6::QIcon.new
    end

    private def selected_database_uris : Array(String)
      tree = @database_tree
      model = @database_model
      return [] of String unless tree && model

      index = tree.current_index
      return [] of String unless index.valid?

      item = model.item_from_index(index)
      return [] of String unless item

      uris = [] of String
      collect_database_uris(item, uris)
      uris.uniq!
      uris
    end

    private def collect_database_uris(item : Qt6::StandardItem, uris : Array(String)) : Nil
      case data = item.data(Qt6::ItemDataRole::User)
      when String
        uris << data unless data.empty?
      end

      item.row_count.times do |row|
        child = item.child(row)
        collect_database_uris(child, uris) if child
      end
    end

    private def append_selected_database_to_queue(insert_row : Int32? = nil) : Bool
      uris = @dragged_database_uris.empty? ? selected_database_uris : @dragged_database_uris.dup
      return false if uris.empty?

      mpd_action do |client|
        client.with_command_list do
          if insert_row && insert_row < @playlist_positions.size
            base_position = @playlist_positions[insert_row]? || insert_row
            uris.each_with_index do |uri, offset|
              client.addid(uri, base_position + offset)
            end
          else
            uris.each { |uri| client.add(uri) }
          end
        end
      end
      suffix = uris.size == 1 ? "song" : "songs"
      action = insert_row ? "Inserted" : "Added"
      set_status("#{action} #{uris.size} #{suffix} from Database")
      @dragged_database_uris.clear
      true
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      false
    end
  end
end
