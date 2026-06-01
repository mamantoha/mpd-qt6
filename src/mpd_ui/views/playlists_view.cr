module MPDUI
  class PlaylistsView
    ROW_TYPE_PLAYLIST = PlaylistsModel::ROW_TYPE_PLAYLIST
    ROW_TYPE_SONG     = PlaylistsModel::ROW_TYPE_SONG

    getter root : Qt6::Widget
    getter song_view : Qt6::TreeView
    getter song_model : PlaylistsModel
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
    @dragged_song_uris : Array(String) = [] of String
    @selected_song_uris_cache : Array(String) = [] of String
    @selected_song_positions_cache : Array(Int32) = [] of Int32
    @selected_song_playlist_name_cache : String?
    @selection_cache_dirty = true
    @playlist_controller = PlaylistController.new

    def initialize(parent : Qt6::Widget)
      @root = Qt6::Widget.new(parent)
      @root.minimum_width = 220
      @song_view = Qt6::TreeView.new(@root)
      @song_model = PlaylistsModel.new(@song_view)
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
      expanded_names = expanded_playlist_names

      @syncing_selection = true
      @song_model.replace(playlists)
      configure_song_header

      name_to_select = previous_name && @song_model.has_playlist?(previous_name) ? previous_name : @song_model.first_playlist_name
      @last_selected_playlist_name = name_to_select
      restore_expanded_playlists(expanded_names)
      select_playlist(name_to_select)
    ensure
      @syncing_selection = false
      update_action_buttons
    end

    def render_message(message : String) : Nil
      @song_model.show_message(message)
      configure_song_header
      update_action_buttons
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
      return @dragged_song_uris.dup unless @dragged_song_uris.empty?

      refresh_selection_cache if @selection_cache_dirty
      @selected_song_uris_cache.dup
    end

    def selected_song_positions : Array(Int32)
      refresh_selection_cache if @selection_cache_dirty
      @selected_song_positions_cache.dup
    end

    private def configure_song_view : Nil
      @song_view.model = @song_model
      @song_view.header_hidden = true
      @song_view.header.stretch_last_section = true
      @song_view.header.set_section_resize_mode(0, Qt6::HeaderResizeMode::Stretch)
      @song_view.root_is_decorated = true
      @song_view.uniform_row_heights = false
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

    private def configure_song_header : Nil
      header = @song_view.header
      header.stretch_last_section = true
      header.set_section_resize_mode(0, Qt6::HeaderResizeMode::Stretch)
    end

    private def expanded_playlist_names : Set(String)
      expanded = Set(String).new

      @song_model.playlist_names.each do |name|
        index = @song_model.index_for_playlist(name)
        next unless index

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
        index = @song_model.index_for_playlist(name)
        next unless index

        begin
          @song_view.expand(index) if index.valid?
        ensure
          index.release
        end
      end
    end

    private def update_action_buttons : Nil
      playlist_selected = !!selected_playlist_name
      refresh_selection_cache if @selection_cache_dirty
      song_selected = !@selected_song_positions_cache.empty?
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

        playlist_name = playlist_name_for_index(index)
        song_position = song_position_for_index(index)
        song_uri = song_uri_for_index(index)
        unless playlist_name && song_position && song_uri
          clear_dragged_song
          return
        end

        selection_model = @song_view.selection_model
        selected_drag = selection_model && selection_model.selected?(index)
        refresh_selection_cache if selected_drag && @selection_cache_dirty

        if selected_drag && @selected_song_playlist_name_cache == playlist_name && @selected_song_positions_cache.includes?(song_position)
          @dragged_song_playlist_name = playlist_name
          @dragged_song_positions = @selected_song_positions_cache.dup
          @dragged_song_uris = @selected_song_uris_cache.dup
        else
          @dragged_song_playlist_name = playlist_name
          @dragged_song_positions = [song_position]
          @dragged_song_uris = [song_uri]
          @selected_song_playlist_name_cache = playlist_name
          @selected_song_positions_cache = @dragged_song_positions.dup
          @selected_song_uris_cache = @dragged_song_uris.dup
          @selection_cache_dirty = false
        end
      ensure
        index.release
      end
    end

    private def clear_dragged_song : Nil
      @dragged_song_playlist_name = nil
      @dragged_song_positions.clear
      @dragged_song_uris.clear
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

      parent_index = parent_index_for_playlist(playlist_name)
      begin
        plan = @playlist_controller.move_plan(@song_model.row_count(parent_index), target.insert_position, @dragged_song_positions)
      ensure
        parent_index.release
      end
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

        playlist_name = playlist_name_for_index(index)
        target_position = song_position_for_index(index)
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
      mark_selection_cache_dirty
      update_action_buttons
      @on_song_selection_changed.try(&.call)
      return if @syncing_selection

      name = selected_playlist_name
      return if name == @last_selected_playlist_name

      @last_selected_playlist_name = name
    end

    private def select_playlist(name : String?) : Nil
      return unless name

      index = @song_model.index_for_playlist(name)
      return unless index

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
        refresh_selection_cache if @selection_cache_dirty
        next if @selected_song_positions_cache.empty?

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

    private def selected_song_indexes : Array(Qt6::ModelIndex)
      selection_model = @song_view.selection_model
      return [] of Qt6::ModelIndex unless selection_model

      selection_model.selected_rows(0).compact_map do |index|
        if index.valid? && song_index?(index)
          index
        else
          index.release
          nil
        end
      end
    end

    private def current_song_indexes : Array(Qt6::ModelIndex)
      index = @song_view.current_index
      unless index.valid? && song_index?(index)
        index.release
        return [] of Qt6::ModelIndex
      end

      [index]
    end

    private def mark_selection_cache_dirty : Nil
      @selection_cache_dirty = true
    end

    private def refresh_selection_cache : Nil
      uris = [] of String
      positions = [] of Int32
      playlist_name : String? = nil

      indexes = selected_song_indexes
      begin
        indexes.each do |index|
          index_playlist_name = playlist_name_for_index(index)
          uri = song_uri_for_index(index)
          position = song_position_for_index(index)
          next unless index_playlist_name && uri && position

          playlist_name ||= index_playlist_name
          next unless playlist_name == index_playlist_name

          uris << uri
          positions << position
        end
      ensure
        indexes.each(&.release)
      end

      if uris.empty?
        indexes = current_song_indexes
        begin
          indexes.each do |index|
            index_playlist_name = playlist_name_for_index(index)
            uri = song_uri_for_index(index)
            position = song_position_for_index(index)
            next unless index_playlist_name && uri && position

            playlist_name = index_playlist_name
            uris << uri
            positions << position
          end
        ensure
          indexes.each(&.release)
        end
      end

      @selected_song_playlist_name_cache = playlist_name
      @selected_song_uris_cache = uris.uniq!
      @selected_song_positions_cache = positions
      @selection_cache_dirty = false
    end

    private def row_type(index : Qt6::ModelIndex) : String?
      return unless index.valid?

      index.data(@song_model, ItemRoles::PLAYLIST_ROW_TYPE).as?(String)
    end

    private def song_uri_for_index(index : Qt6::ModelIndex) : String?
      return unless row_type(index) == ROW_TYPE_SONG

      uri = index.data(@song_model, ItemRoles::PLAYLIST_SONG_URI).as?(String)
      uri unless uri.nil? || uri.empty?
    end

    private def song_position_for_index(index : Qt6::ModelIndex) : Int32?
      return unless row_type(index) == ROW_TYPE_SONG

      index.data(@song_model, ItemRoles::PLAYLIST_SONG_POSITION).as?(Int32)
    end

    private def parent_index_for_playlist(name : String) : Qt6::ModelIndex
      @song_model.index_for_playlist(name) || Qt6::ModelIndex.new
    end
  end
end
