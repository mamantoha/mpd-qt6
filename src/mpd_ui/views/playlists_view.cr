module MPDUI
  class PlaylistsView
    ROW_TYPE_PLAYLIST = "playlist"
    ROW_TYPE_SONG     = "song"

    getter root : Qt6::Widget
    getter song_view : Qt6::TreeView
    getter song_model : Qt6::StandardItemModel
    getter context_filter : Qt6::EventFilter?
    getter song_drag_filter : Qt6::EventFilter?

    property on_refresh : Proc(Nil)?
    property on_replace_queue : Proc(Nil)?
    property on_add_to_queue : Proc(Nil)?
    property on_rename : Proc(Nil)?
    property on_delete : Proc(Nil)?
    property on_add_songs_to_queue : Proc(Nil)?
    property on_remove_songs : Proc(Nil)?
    property on_move_songs : Proc(String, Array(Tuple(Int32, Int32)), Nil)?
    property on_song_selection_changed : Proc(Nil)?
    property on_song_mouse_press : Proc(Nil)?
    property on_song_drag_enter : Proc(Nil)?
    property on_song_drag_finished : Proc(Nil)?

    @playlists : Array(PlaylistEntry) = [] of PlaylistEntry
    @playlist_songs : Hash(String, Array(Song)) = {} of String => Array(Song)
    @playlist_items : Hash(String, Qt6::StandardItem) = {} of String => Qt6::StandardItem
    @loaded_playlist_names = Set(String).new
    @last_selected_playlist_name : String?
    @syncing_selection = false
    @delegate : Qt6::StyledItemDelegate
    @context_menu : Qt6::Menu
    @replace_queue_action : Qt6::Action
    @add_to_queue_action : Qt6::Action
    @rename_action : Qt6::Action
    @delete_action : Qt6::Action
    @song_context_menu : Qt6::Menu
    @add_songs_to_queue_action : Qt6::Action
    @remove_songs_action : Qt6::Action
    @song_shortcuts : Array(Qt6::Shortcut) = [] of Qt6::Shortcut
    @dragged_song_playlist_name : String?
    @dragged_song_positions : Array(Int32) = [] of Int32
    @playlist_controller = PlaylistController.new

    def initialize(parent : Qt6::Widget)
      @root = Qt6::Widget.new(parent)
      @root.minimum_width = 220
      @song_view = Qt6::TreeView.new(@root)
      @song_model = Qt6::StandardItemModel.new(@song_view)
      configure_song_view
      @delegate = TwoLineItemDelegate.build(@song_view, @song_model)
      @song_view.item_delegate = @delegate

      @context_menu = Qt6::Menu.new("Playlist", @song_view)
      add_context_action("Refresh", "view-refresh") { @on_refresh.try(&.call) }
      @context_menu.add_separator
      @replace_queue_action = add_context_action("Replace Play Queue", "media-playback-start") { @on_replace_queue.try(&.call) }
      @add_to_queue_action = add_context_action("Add To Play Queue", "list-add") { @on_add_to_queue.try(&.call) }
      @context_menu.add_separator
      @rename_action = add_context_action("Rename", "edit-rename") { @on_rename.try(&.call) }
      @delete_action = add_context_action("Delete", "edit-delete") { @on_delete.try(&.call) }
      @song_context_menu = Qt6::Menu.new("Playlist Songs", @song_view)
      @add_songs_to_queue_action = add_song_context_action("Add to Queue", "list-add") { @on_add_songs_to_queue.try(&.call) }
      @remove_songs_action = add_song_context_action("Remove From Playlist", "edit-delete") { @on_remove_songs.try(&.call) }
      add_song_shortcut("Delete") { @on_remove_songs.try(&.call) }
      update_action_buttons

      @song_view.on_current_index_changed { handle_current_index_changed }
      install_song_drag_filter

      @root.vbox do |column|
        column.spacing = 0
        column.set_contents_margins(0, 0, 0, 0)
        column << @song_view
      end
    end

    def render_playlists(playlists : Array(PlaylistEntry)) : Nil
      previous_name = selected_playlist_name
      @playlists = playlists
      @playlist_songs.select! { |name, _songs| @playlists.any? { |playlist| playlist.name == name } }
      @playlists.each do |playlist|
        @playlist_songs[playlist.name] = playlist.songs
      end

      if @playlists.empty?
        @last_selected_playlist_name = nil
        render_message("No stored playlists")
      else
        render_tree(previous_name || @playlists.first.name)
      end

      update_action_buttons
    end

    def render_message(message : String) : Nil
      @song_model.clear
      @playlist_items.clear
      @loaded_playlist_names.clear
      configure_song_model
      configure_song_header

      item = Qt6::StandardItem.new(message)
      item.flags = Qt6::ItemFlag::Enabled
      @song_model << item
    end

    def selected_playlist_name : String?
      index = @song_view.current_index
      begin
        return playlist_name_for_index(index) if index.valid?
      ensure
        index.release
      end

      @last_selected_playlist_name
    end

    def selected_song_uris : Array(String)
      items = selected_song_items
      items = current_song_items if items.empty?

      items.compact_map { |item| song_uri_for_item(item) }.uniq!
    end

    def selected_song_positions : Array(Int32)
      items = selected_song_items
      items = current_song_items if items.empty?

      items.compact_map { |item| song_position_for_item(item) }
    end

    private def configure_song_view : Nil
      configure_song_model
      @song_view.model = @song_model
      @song_view.header_hidden = true
      @song_view.header.stretch_last_section = true
      @song_view.header.set_section_resize_mode(0, Qt6::HeaderResizeMode::Stretch)
      @song_view.root_is_decorated = true
      @song_view.uniform_row_heights = false
      @song_view.icon_size = Qt6::Size.new(24, 24)
      @song_view.alternating_row_colors = true
      @song_view.selection_mode = Qt6::ItemSelectionMode::ExtendedSelection
      @song_view.selection_behavior = Qt6::ItemSelectionBehavior::SelectRows
      @song_view.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      @song_view.drag_enabled = true
      @song_view.accept_drops = true
      @song_view.drag_drop_mode = Qt6::ItemViewDragDropMode::DragDrop
      @song_view.drag_drop_overwrite_mode = false
      @song_view.default_drop_action = Qt6::DropAction::MoveAction
      @song_view.drop_indicator_shown = true
      @song_view.minimum_width = 220
      @song_view.style_sheet = <<-CSS
        QTreeView {
          border: none;
        }
        QTreeView::item {
          padding: 3px 0px;
        }
        CSS
      configure_song_header
    end

    private def configure_song_model : Nil
      @song_model.set_horizontal_header_label(0, "Playlist")
    end

    private def configure_song_header : Nil
      header = @song_view.header
      header.stretch_last_section = true
      header.set_section_resize_mode(0, Qt6::HeaderResizeMode::Stretch)
    end

    private def render_tree(selected_name : String?) : Nil
      expanded_names = expanded_playlist_names
      @syncing_selection = true
      @song_model.clear
      @playlist_items.clear
      @loaded_playlist_names.clear
      configure_song_model
      configure_song_header

      playlist_icon = Qt6::QIcon.from_theme("view-media-playlist")
      @playlists.each_with_index do |playlist, row|
        playlist_item = TwoLineItemDelegate.item(playlist.name, playlist_subtitle(playlist))
        playlist_item.icon = playlist_icon unless playlist_icon.null?
        playlist_item.set_data(ROW_TYPE_PLAYLIST, ItemRoles::PLAYLIST_ROW_TYPE)
        playlist_item.set_data(playlist.name, ItemRoles::PLAYLIST_NAME)
        playlist_item.set_data(playlist.tooltip, Qt6::ItemDataRole::ToolTip)
        playlist_item.flags = Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable | Qt6::ItemFlag::DropEnabled

        @song_model.set_item(row, 0, playlist_item)
        @playlist_items[playlist.name] = playlist_item

        append_playlist_placeholder(playlist.name, playlist_item)
      end

      name_to_select = selected_name && @playlist_items.has_key?(selected_name) ? selected_name : @playlists.first?.try(&.name)
      @last_selected_playlist_name = name_to_select
      restore_expanded_playlists(expanded_names)
      select_playlist(name_to_select)
    ensure
      @syncing_selection = false
    end

    private def append_playlist_placeholder(playlist_name : String, playlist_item : Qt6::StandardItem) : Nil
      songs = @playlist_songs[playlist_name]?
      return unless songs && !songs.empty?

      placeholder = Qt6::StandardItem.new("")
      placeholder.flags = Qt6::ItemFlag::None
      playlist_item.set_child(0, 0, placeholder)
    end

    private def ensure_playlist_songs_loaded(playlist_name : String) : Nil
      return if @loaded_playlist_names.includes?(playlist_name)

      playlist_item = @playlist_items[playlist_name]?
      return unless playlist_item

      append_playlist_songs(playlist_name, playlist_item)
      @loaded_playlist_names << playlist_name
    end

    private def ensure_playlist_songs_loaded_at(position : Qt6::PointF) : Nil
      index = @song_view.index_at(position)
      begin
        return unless index.valid?

        name = playlist_name_for_index(index)
        ensure_playlist_songs_loaded(name) if name
      ensure
        index.release
      end
    end

    private def append_playlist_songs(playlist_name : String, playlist_item : Qt6::StandardItem) : Nil
      songs = @playlist_songs[playlist_name]?
      return unless songs

      music_icon = Qt6::QIcon.from_theme("audio-x-generic")
      songs.each_with_index do |song, row|
        title_item = TwoLineItemDelegate.item(song.title, song.subtitle)
        title_item.icon = music_icon unless music_icon.null?
        configure_song_item(title_item)
        title_item.set_data(ROW_TYPE_SONG, ItemRoles::PLAYLIST_ROW_TYPE)
        title_item.set_data(playlist_name, ItemRoles::PLAYLIST_NAME)
        title_item.set_data(row, ItemRoles::PLAYLIST_SONG_POSITION)
        title_item.set_data(song.file || "", ItemRoles::PLAYLIST_SONG_URI)
        title_item.set_data(song.tooltip_html, Qt6::ItemDataRole::ToolTip)

        playlist_item.set_child(row, 0, title_item)
      end
    end

    private def configure_song_item(item : Qt6::StandardItem) : Nil
      item.flags = Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable | Qt6::ItemFlag::DragEnabled
    end

    private def expanded_playlist_names : Set(String)
      expanded = Set(String).new

      @playlist_items.each do |name, item|
        index = @song_model.index_from_item(item)
        begin
          expanded << name if index.valid? && @song_view.expanded?(index)
        ensure
          index.release
        end
      end

      expanded
    end

    private def restore_expanded_playlists(names : Set(String)) : Nil
      names.each do |name|
        item = @playlist_items[name]?
        next unless item

        ensure_playlist_songs_loaded(name)
        index = @song_model.index_from_item(item)
        begin
          @song_view.expand(index) if index.valid?
        ensure
          index.release
        end
      end
    end

    private def update_action_buttons : Nil
      playlist_selected = !!selected_playlist_name
      song_selected = !selected_song_positions.empty?
      @replace_queue_action.enabled = playlist_selected
      @add_to_queue_action.enabled = playlist_selected
      @rename_action.enabled = playlist_selected
      @delete_action.enabled = playlist_selected
      @add_songs_to_queue_action.enabled = song_selected
      @remove_songs_action.enabled = song_selected
    end

    private def install_song_drag_filter : Nil
      viewport = @song_view.viewport
      viewport.accept_drops = true

      filter = Qt6::EventFilter.new(viewport)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          mouse_event = event.mouse_event
          if mouse_event.button == 2
            show_context_menu(viewport, mouse_event.position)
            true
          else
            ensure_playlist_songs_loaded_at(mouse_event.position)
            if song_index_at?(mouse_event.position)
              remember_dragged_song(mouse_event.position)
              @on_song_mouse_press.try(&.call)
            end
            false
          end
        when Qt6::EventType::DragEnter
          @on_song_drag_enter.try(&.call) if current_song?
          false
        when Qt6::EventType::Drop
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          if internal_song_drag?
            drop_event.ignore unless handle_internal_song_drop(drop_event)
            @on_song_drag_finished.try(&.call)
            clear_dragged_song
            true
          else
            clear_dragged_song
            @on_song_drag_finished.try(&.call)
            false
          end
        when Qt6::EventType::MouseButtonRelease
          clear_dragged_song
          false
        when Qt6::EventType::DragLeave
          false
        else
          false
        end
      end

      viewport.install_event_filter(filter)
      @song_drag_filter = filter
      @context_filter = filter
    end

    private def remember_dragged_song(position : Qt6::PointF) : Nil
      index = @song_view.index_at(position)
      begin
        unless index.valid? && song_index?(index)
          clear_dragged_song
          return
        end

        item = @song_model.item_from_index(index)
        playlist_name = item.try(&.data(ItemRoles::PLAYLIST_NAME).as?(String))
        position = item.try(&.data(ItemRoles::PLAYLIST_SONG_POSITION).as?(Int32))
        unless playlist_name && position
          clear_dragged_song
          return
        end

        selected_positions = selected_song_items.compact_map do |selected_item|
          next unless selected_item.data(ItemRoles::PLAYLIST_NAME).as?(String) == playlist_name

          selected_item.data(ItemRoles::PLAYLIST_SONG_POSITION).as?(Int32)
        end

        @dragged_song_playlist_name = playlist_name
        @dragged_song_positions = selected_positions.includes?(position) ? selected_positions : [position]
      ensure
        index.release
      end
    end

    private def clear_dragged_song : Nil
      @dragged_song_playlist_name = nil
      @dragged_song_positions.clear
    end

    private def internal_song_drag? : Bool
      !!@dragged_song_playlist_name && !@dragged_song_positions.empty?
    end

    private def handle_internal_song_drop(event : Qt6::DropEvent) : Bool
      playlist_name = @dragged_song_playlist_name
      return false unless playlist_name

      target = song_drop_target(event.position)
      return false unless target
      return false unless target.playlist_name == playlist_name

      songs = @playlist_songs[playlist_name]?
      return false unless songs

      plan = @playlist_controller.move_plan(songs.size, target.insert_position, @dragged_song_positions)
      return false unless plan
      callback = @on_move_songs
      return false unless callback

      callback.call(playlist_name, plan.moves)
      event.drop_action = Qt6::DropAction::MoveAction
      event.accept
      true
    end

    private record SongDropTarget, playlist_name : String, insert_position : Int32

    private def song_drop_target(position : Qt6::PointF) : SongDropTarget?
      index = @song_view.index_at(position)
      begin
        return unless index.valid? && song_index?(index)

        item = @song_model.item_from_index(index)
        return unless item

        playlist_name = item.data(ItemRoles::PLAYLIST_NAME).as?(String)
        target_position = item.data(ItemRoles::PLAYLIST_SONG_POSITION).as?(Int32)
        return unless playlist_name && target_position

        rect = @song_view.visual_rect(index)
        insert_position = position.y < rect.y + rect.height / 2.0 ? target_position : target_position + 1
        SongDropTarget.new(playlist_name, insert_position)
      ensure
        index.release
      end
    end

    private def show_context_menu(viewport : Qt6::Widget, position : Qt6::PointF) : Nil
      index = @song_view.index_at(position)
      begin
        return unless index.valid?

        select_index_if_needed(index)
        update_action_buttons

        if song_index?(index)
          @song_context_menu.exec_at(viewport, position)
        else
          @context_menu.exec_at(viewport, position)
        end
      ensure
        index.release
      end
    end

    private def select_index_if_needed(index : Qt6::ModelIndex) : Nil
      selection_model = @song_view.selection_model
      unless selection_model && selection_model.selected?(index)
        selection_model.try(&.set_current_index(index, Qt6::SelectionFlag::ClearAndSelect | Qt6::SelectionFlag::Rows))
        @song_view.current_index = index
      end
    end

    private def handle_current_index_changed : Nil
      update_action_buttons
      @on_song_selection_changed.try(&.call)
      return if @syncing_selection

      name = selected_playlist_name
      ensure_playlist_songs_loaded(name) if name
      return if name == @last_selected_playlist_name

      @last_selected_playlist_name = name
    end

    private def select_playlist(name : String?) : Nil
      item = name.try { |value| @playlist_items[value]? }
      return unless item

      index = @song_model.index_from_item(item)
      begin
        @song_view.selection_model.try(&.set_current_index(index, Qt6::SelectionFlag::ClearAndSelect | Qt6::SelectionFlag::Rows))
        @song_view.current_index = index
      ensure
        index.release
      end
    end

    private def add_context_action(label : String, icon_name : String, &block : ->) : Qt6::Action
      action = Qt6::Action.new(label, @song_view)
      icon = Qt6::QIcon.from_theme(icon_name)
      action.icon = icon unless icon.null?
      action.on_triggered { block.call }
      @context_menu.add_action(action)
      action
    end

    private def add_song_context_action(label : String, icon_name : String, &block : ->) : Qt6::Action
      action = Qt6::Action.new(label, @song_view)
      icon = Qt6::QIcon.from_theme(icon_name)
      action.icon = icon unless icon.null?
      action.on_triggered { block.call }
      @song_context_menu.add_action(action)
      action
    end

    private def add_song_shortcut(shortcut : String, &block : ->) : Qt6::Shortcut
      action = Qt6::Shortcut.new(shortcut, @song_view)
      action.context = Qt6::ShortcutContext::WidgetWithChildrenShortcut
      action.on_activated do
        next unless @song_view.has_focus? || @song_view.viewport.has_focus?
        next if selected_song_positions.empty?

        block.call
      end
      @song_shortcuts << action
      action
    end

    private def current_song? : Bool
      index = @song_view.current_index
      begin
        song_index?(index)
      ensure
        index.release
      end
    end

    private def song_index_at?(position : Qt6::PointF) : Bool
      index = @song_view.index_at(position)
      begin
        song_index?(index)
      ensure
        index.release
      end
    end

    private def song_index?(index : Qt6::ModelIndex) : Bool
      row_type(index) == ROW_TYPE_SONG
    end

    private def playlist_name_for_index(index : Qt6::ModelIndex) : String?
      return unless index.valid?

      index.data(@song_model, ItemRoles::PLAYLIST_NAME).as?(String)
    end

    private def selected_song_items : Array(Qt6::StandardItem)
      selection_model = @song_view.selection_model
      return [] of Qt6::StandardItem unless selection_model

      selection_model.selected_rows(0).compact_map do |index|
        begin
          next unless index.valid? && song_index?(index)

          @song_model.item_from_index(index)
        ensure
          index.release
        end
      end
    end

    private def current_song_items : Array(Qt6::StandardItem)
      index = @song_view.current_index
      begin
        return [] of Qt6::StandardItem unless index.valid? && song_index?(index)

        item = @song_model.item_from_index(index)
        item ? [item] : [] of Qt6::StandardItem
      ensure
        index.release
      end
    end

    private def row_type(index : Qt6::ModelIndex) : String?
      return unless index.valid?

      index.data(@song_model, ItemRoles::PLAYLIST_ROW_TYPE).as?(String)
    end

    private def song_uri_for_item(item : Qt6::StandardItem) : String?
      return unless item.data(ItemRoles::PLAYLIST_ROW_TYPE).as?(String) == ROW_TYPE_SONG

      uri = item.data(ItemRoles::PLAYLIST_SONG_URI).as?(String)
      uri unless uri.nil? || uri.empty?
    end

    private def song_position_for_item(item : Qt6::StandardItem) : Int32?
      return unless item.data(ItemRoles::PLAYLIST_ROW_TYPE).as?(String) == ROW_TYPE_SONG

      item.data(ItemRoles::PLAYLIST_SONG_POSITION).as?(Int32)
    end

    private def playlist_subtitle(playlist : PlaylistEntry) : String?
      return playlist.summary if playlist.summary

      songs = @playlist_songs[playlist.name]?
      return unless songs
      count = songs.size
      total = songs.compact_map(&.duration).sum
      "#{count} #{count == 1 ? "Track" : "Tracks"} (#{Song.format_time(total)})"
    end
  end
end
