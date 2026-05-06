require "json"

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
      tree.uniform_row_heights = false
      tree.icon_size = Qt6::Size.new(24, 24)
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
          border: none;
        }
        QTreeView::item {
          padding: 0px;
        }
        CSS

      delegate = build_database_item_delegate(tree, model)
      tree.item_delegate = delegate

      tree.on_current_index_changed do
        @playlist_drag_source_row = nil
        @dragged_database_uris = selected_database_uris
      end

      context_menu = Qt6::Menu.new("Library", tree)
      add_to_queue_action = Qt6::Action.new("Add to Queue", tree)
      add_icon = Qt6::QIcon.from_theme("list-add")
      add_to_queue_action.icon = add_icon unless add_icon.null?
      add_to_queue_action.on_triggered { add_selected_database_to_queue }
      context_menu.add_action(add_to_queue_action)

      search_edit.on_text_changed do |_text|
        apply_database_filter
      end

      close_search_button.on_clicked { hide_database_search }
      escape_shortcut = Qt6::Shortcut.new("Esc", search_edit)
      escape_shortcut.context = Qt6::ShortcutContext::WidgetShortcut
      escape_shortcut.on_activated do
        hide_database_search if search_edit.has_focus?
      end

      search_panel.hbox do |row|
        row.spacing = 4
        row.set_contents_margins(4, 4, 4, 2)
        row << search_edit
        row << close_search_button
      end

      container.vbox do |column|
        column.spacing = 0
        column.set_contents_margins(0, 0, 0, 0)
        column << search_panel
        column << tree
      end

      @database_search_panel = search_panel
      @database_search_edit = search_edit
      @database_search_escape_shortcut = escape_shortcut
      @database_tree = tree
      @database_context_menu = context_menu
      @database_model = model
      @database_item_delegate = delegate
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
          mouse_event = event.mouse_event
          if mouse_event.button == 2
            show_database_context_menu(tree, viewport, mouse_event.position)
            true
          else
            @playlist_drag_source_row = nil
            @dragged_database_uris.clear
            @drag_source_type = :database
            false
          end
        when Qt6::EventType::DragEnter
          @drag_source_type = :database
          false
        when Qt6::EventType::DragLeave, Qt6::EventType::Drop
          @drag_source_type = nil
          false
        else
          false
        end
      end

      viewport.install_event_filter(filter)
      @database_drag_filter = filter
    end

    private def show_database_context_menu(tree : Qt6::TreeView, viewport : Qt6::Widget, position : Qt6::PointF) : Nil
      index = tree.index_at(position)
      begin
        return unless index.valid?

        selection_model = tree.selection_model
        unless selection_model && selection_model.selected?(index)
          selection_model.try(&.set_current_index(index, Qt6::SelectionFlag::ClearAndSelect))
          tree.current_index = index
        end

        @dragged_database_uris.clear
        @database_context_menu.try(&.exec_at(viewport, position))
      ensure
        index.release
      end
    end

    private def build_database_item_delegate(tree : Qt6::TreeView, model : Qt6::StandardItemModel) : Qt6::StyledItemDelegate
      delegate = Qt6::StyledItemDelegate.new(tree)
      delegate.on_paint do |painter, option, index|
        payload = parse_database_item_payload(index.data(model).as?(String))
        next false unless payload

        title = payload["title"].not_nil!
        subtitle = payload["subtitle"]?

        option.draw_background(painter)
        option.draw_decoration(painter)

        rect = option.text_rect
        title_font = option.font
        title_font.bold = true
        subtitle_font = option.font
        if subtitle_font.point_size > 0
          subtitle_font.point_size = Math.max(1, (subtitle_font.point_size * 0.86).round.to_i)
        end

        title_metrics = title_font.metrics
        subtitle_metrics = subtitle_font.metrics
        title_height = title_metrics.height
        subtitle_height = subtitle_metrics.height
        text_height = subtitle && !subtitle.empty? ? title_height + subtitle_height : title_height
        top = rect.y + Math.max(0.0, (rect.height - text_height) / 2.0)

        palette = option.palette
        title_color = option.selected? ? palette.color(Qt6::ColorRole::HighlightedText) : palette.color(Qt6::ColorRole::Text)
        subtitle_color = option.selected? ? title_color : palette.color(Qt6::ColorGroup::Disabled, Qt6::ColorRole::Text)

        painter.save
        painter.font = title_font
        painter.pen = title_color
        painter.draw_text(Qt6::RectF.new(rect.x, top, rect.width, title_height.to_f64), Qt6::AlignmentFlag::Left | Qt6::AlignmentFlag::VCenter, title)
        if subtitle && !subtitle.empty?
          painter.font = subtitle_font
          painter.pen = subtitle_color
          painter.draw_text(Qt6::RectF.new(rect.x, top + title_height, rect.width, subtitle_height.to_f64), Qt6::AlignmentFlag::Left | Qt6::AlignmentFlag::VCenter, subtitle)
        end
        painter.restore
        true
      end
      delegate.on_size_hint do |_option, index|
        payload = parse_database_item_payload(index.data(model).as?(String))
        subtitle = payload.try(&.["subtitle"]?)
        subtitle && !subtitle.empty? ? Qt6::Size.new(0, 42) : nil
      end
      delegate
    end

    private def add_selected_database_to_queue : Nil
      @dragged_database_uris.clear
      append_selected_database_to_queue
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

      run_background(
        ->(songs : Array(Song)) {
          @database_songs = songs
          @database_loaded = true
          @database_loading = false
          apply_database_filter
        },
        ->(ex : Exception) {
          @database_loaded = false
          @database_loading = false
          show_database_message("Failed to load database")
          set_status("Database load failed: #{ex.message || ex}")
        }
      ) do
        db_client = nil
        db_client = MPD::Client.new(host, port)
        if update_mpd
          db_client.update
          wait_for_mpd_database_update(db_client)
        end
        raw_entries = db_client.listallinfo
        database_song_entries(raw_entries)
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
      model = @database_model
      return unless model

      model.clear
      model.set_horizontal_header_label(0, "Database")
      model << Qt6::StandardItem.new(message)
    end

    private def database_song_entries(entries : MPD::Object | MPD::Objects?) : Array(Song)
      return [] of Song unless entries

      case entries
      when Array
        entries.select { |entry| !!entry["file"]? }.map { |entry| Song.from_mpd(entry) }
      else
        entries["file"]? ? [Song.from_mpd(entries)] : [] of Song
      end
    end

    private def build_database_library(songs : Array(Song)) : Hash(String, Hash(String, Array(Song)))
      library = Hash(String, Hash(String, Array(Song))).new do |artists, artist|
        artists[artist] = Hash(String, Array(Song)).new do |albums, album|
          albums[album] = [] of Song
        end
      end

      songs.each do |song|
        artist = display_name(song.artist, "[Unknown Artist]")
        album = display_name(song.album, "[Unknown Album]")
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

    private def database_song_matches?(song : Song, terms : Array(String)) : Bool
      haystack = [
        song.artist,
        song.album,
        song.title,
        song.file,
      ].compact.join(" ").downcase

      terms.all? { |term| haystack.includes?(term) }
    end

    private def populate_database_tree(library : Hash(String, Hash(String, Array(Song))), *, filtered : Bool = false) : Nil
      model = @database_model
      return unless model

      model.clear
      model.set_horizontal_header_label(0, "Database")

      if library.empty?
        model << database_item(filtered ? "No matching songs" : "Database is empty")
        return
      end

      artist_icon = themed_icon("user-identiry", "person.circle")
      album_icon = themed_icon("media-optical-audio", "media-optical")
      song_icon = themed_icon("audio-x-generic", "music.note.list")

      library.keys.sort!.each do |artist|
        artist_albums = library[artist]
        artist_item = database_item(artist, "#{artist_albums.size} #{artist_albums.size == 1 ? "Album" : "Albums"}")
        artist_item.icon = artist_icon unless artist_icon.null?

        artist_albums.keys.sort_by! { |album| album_sort_key(album, artist_albums[album]) }.each do |album|
          album_songs = artist_albums[album]
          album_item = database_item(album, database_album_summary(album_songs))
          album_item.icon = album_icon unless album_icon.null?

          album_songs.sort_by { |song| song_sort_key(song) }.each do |song|
            song_item = database_item(database_song_title(song), playlist_duration(song), song.file)
            song_item.icon = song_icon unless song_icon.null?
            song_item.set_data(song_tooltip(song), Qt6::ItemDataRole::ToolTip)
            album_item << song_item
          end

          artist_item << album_item
        end

        model << artist_item
      end

      @database_tree.try(&.expand_all) if filtered
    end

    private def album_sort_key(album : String, songs : Array(Song)) : Tuple(Int32, String)
      {album_year(songs), album.downcase}
    end

    private def album_year(songs : Array(Song)) : Int32
      years = songs.compact_map(&.year)
      years.min? || Int32::MAX
    end

    private def song_sort_key(song : Song) : Tuple(Int32, Int32, String)
      {disc_number(song), track_number(song), database_song_label(song).downcase}
    end

    private def database_item(title : String, subtitle : String? = nil, file : String? = nil) : Qt6::StandardItem
      Qt6::StandardItem.new(build_database_item_payload(title, subtitle, file))
    end

    private def build_database_item_payload(title : String, subtitle : String? = nil, file : String? = nil) : String
      JSON.build do |json|
        json.object do
          json.field "title", title
          json.field "subtitle", subtitle if subtitle
          json.field "file", file if file
        end
      end
    end

    private def parse_database_item_payload(value : String?) : Hash(String, String)?
      return unless value

      json = JSON.parse(value)
      title = json["title"]?.try(&.as_s?)
      return unless title

      payload = {"title" => title}
      if subtitle = json["subtitle"]?.try(&.as_s?)
        payload["subtitle"] = subtitle
      end
      if file = json["file"]?.try(&.as_s?)
        payload["file"] = file
      end
      payload
    rescue JSON::ParseException
      nil
    end

    private def database_album_summary(songs : Array(Song)) : String
      duration = songs.sum { |song| song.duration || 0.0 }
      "#{songs.size} #{songs.size == 1 ? "Track" : "Tracks"}#{duration > 0 ? " (#{format_time(duration)})" : ""}"
    end

    private def database_song_title(song : Song) : String
      song.database_label.split(" • ", 2).first
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
      if file = parse_database_item_payload(item.text).try(&.["file"]?)
        uris << file unless file.empty?
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
          if base_position = @queue_controller.base_position_for_insert(insert_row)
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
