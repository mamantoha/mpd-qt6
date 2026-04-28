module MPDUI
  module AppDatabase
    private def build_database_browser(parent : Qt6::Widget) : Qt6::Widget
      container = Qt6::Widget.new(parent)

      search_panel = Qt6::Widget.new(container)
      search_panel.visible = false
      search_edit = Qt6::LineEdit.new("", search_panel)
      search_edit.placeholder_text = "Search..."
      close_search_button = Qt6::PushButton.new("x", search_panel)
      close_icon = Qt6::QIcon.from_theme("window-close")
      unless close_icon.null?
        close_search_button.icon = close_icon
        close_search_button.text = ""
      end
      close_search_button.fixed_width = 34
      close_search_button.tool_tip = "Close search"

      tree = Qt6::TreeView.new(container)
      model = Qt6::StandardItemModel.new(tree)

      model.set_horizontal_header_label(0, "Database")
      tree.model = model
      tree.header_hidden = true
      tree.root_is_decorated = true
      tree.uniform_row_heights = true
      tree.selection_mode = Qt6::ItemSelectionMode::ExtendedSelection
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

      search_edit.on_text_changed do |_text|
        apply_database_filter
      end

      close_search_button.on_clicked { hide_database_search }

      search_panel.hbox do |row|
        row.spacing = 4
        row.set_contents_margins(0, 0, 0, 0)
        row << search_edit
        row << close_search_button
      end

      container.vbox do |column|
        column << search_panel
        column << tree
      end

      @database_search_panel = search_panel
      @database_search_edit = search_edit
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
          @dragged_database_uris.clear
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

    private def show_database_search : Nil
      return unless @settings.expanded_interface
      return unless @settings.show_library

      preserve_window_size do
        set_library_panel_visible(true)
        @database_search_panel.try(&.visible = true)
      end

      @database_search_edit.try do |edit|
        edit.set_focus
        edit.select_all
      end
    end

    private def hide_database_search : Nil
      @database_search_edit.try do |edit|
        if edit.text.empty?
          apply_database_filter
        else
          edit.clear
        end
      end

      preserve_window_size do
        @database_search_panel.try(&.visible = false)
      end

      @database_tree.try(&.set_focus)
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

      Thread.new do
        db_client = nil
        begin
          db_client = MPD::Client.new(host, port)
          if update_mpd
            db_client.update
            wait_for_mpd_database_update(db_client)
          end
          raw_entries = db_client.listallinfo
          songs = database_song_entries(raw_entries)

          @qt_app.invoke_later do
            @database_songs = songs
            @database_loaded = true
            @database_loading = false
            apply_database_filter
          end
        rescue ex
          @qt_app.invoke_later do
            @database_loaded = false
            @database_loading = false
            show_database_message("Failed to load database")
            set_status("Database load failed: #{ex.message || ex}")
          end
        ensure
          db_client.try(&.disconnect)
        end
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

    private def apply_database_filter : Nil
      query = @database_search_edit.try(&.text.strip) || ""
      terms = query.downcase.split.reject(&.empty?)
      songs = terms.empty? ? @database_songs : @database_songs.select { |song| database_song_matches?(song, terms) }

      populate_database_tree(build_database_library(songs), filtered: !terms.empty?)
      @dragged_database_uris.clear

      if terms.empty?
        set_status("Database loaded • #{@database_songs.size} songs") if @database_loaded
      else
        set_status("Database filter: #{songs.size} of #{@database_songs.size} songs")
      end
    end

    private def database_song_matches?(song : Hash(String, String), terms : Array(String)) : Bool
      haystack = [
        song["Artist"]?,
        song["Album"]?,
        song["Title"]?,
        song["file"]?,
      ].compact.join(" ").downcase

      terms.all? { |term| haystack.includes?(term) }
    end

    private def populate_database_tree(library : Hash(String, Hash(String, Array(Hash(String, String)))), *, filtered : Bool = false) : Nil
      model = @database_model
      return unless model

      model.clear
      model.set_horizontal_header_label(0, "Database")

      if library.empty?
        model << Qt6::StandardItem.new(filtered ? "No matching songs" : "Database is empty")
        return
      end

      artist_icon = themed_icon("user-identiry", "person.circle")
      album_icon = themed_icon("media-optical-audio", "media-optical")
      song_icon = themed_icon("audio-x-generic", "music.note.list")

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

      @database_tree.try(&.expand_all) if filtered
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

      if selection_model = tree.selection_model
        uris = [] of String
        model.row_count.times do |row|
          if item = model.item(row)
            collect_selected_database_uris(item, selection_model, model, uris)
          end
        end
        uris.uniq!
        return uris unless uris.empty?
      end

      index = tree.current_index
      return [] of String unless index.valid?

      item = model.item_from_index(index)
      return [] of String unless item

      uris = [] of String
      collect_database_uris(item, uris)
      uris.uniq!
      uris
    end

    private def collect_selected_database_uris(item : Qt6::StandardItem, selection_model : Qt6::ItemSelectionModel, model : Qt6::StandardItemModel, uris : Array(String)) : Nil
      index = model.index_from_item(item)
      begin
        collect_database_uris(item, uris) if selection_model.selected?(index)
      ensure
        index.release
      end

      item.row_count.times do |row|
        if child = item.child(row)
          collect_selected_database_uris(child, selection_model, model, uris)
        end
      end
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
