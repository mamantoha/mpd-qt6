module MPDUI
  module AppQueue
    private def build_playlist(parent : Qt6::Widget) : Qt6::TreeView
      view = Qt6::TreeView.new(parent)
      model = Qt6::StandardItemModel.new(view)
      model.set_horizontal_header_label(0, "State")
      model.set_horizontal_header_label(1, "Track")
      model.set_horizontal_header_label(2, "Time")

      view.model = model
      view.header_hidden = true
      view.root_is_decorated = false
      view.uniform_row_heights = true
      view.alternating_row_colors = true
      view.selection_mode = Qt6::ItemSelectionMode::ExtendedSelection
      view.selection_behavior = Qt6::ItemSelectionBehavior::SelectRows
      view.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      view.drag_enabled = true
      view.accept_drops = true
      view.drag_drop_mode = Qt6::ItemViewDragDropMode::DragDrop
      view.drag_drop_overwrite_mode = false
      view.default_drop_action = Qt6::DropAction::MoveAction
      view.drop_indicator_shown = true
      view.minimum_height = 320

      view.style_sheet = <<-CSS
        QTreeView {
          border: none;
        }
        QTreeView::item {
          padding: 0px;
        }
      CSS

      view.header.stretch_last_section = false
      configure_playlist_header(view)

      context_menu = Qt6::Menu.new("Queue", view)
      play_now_action = Qt6::Action.new("Play Now", view)
      play_now_icon = Qt6::QIcon.from_theme("media-playback-start")
      play_now_action.icon = play_now_icon unless play_now_icon.null?
      play_now_action.on_triggered { play_selected_playlist_row }
      context_menu.add_action(play_now_action)

      remove_action = Qt6::Action.new("Remove from Queue", view)
      remove_icon = Qt6::QIcon.from_theme("edit-delete")
      remove_action.icon = remove_icon unless remove_icon.null?
      remove_action.on_triggered { delete_selected_playlist_row }
      context_menu.add_action(remove_action)
      @queue_context_menu = context_menu
      @queue_play_now_action = play_now_action

      play_return_action = Qt6::Action.new("Play Selected", view)
      play_return_action.shortcut = "Return"
      play_return_action.on_triggered do
        next unless view.has_focus? || view.viewport.has_focus?
        play_selected_playlist_row
      end
      view.add_action(play_return_action)
      @play_queue_return_action = play_return_action

      play_enter_action = Qt6::Action.new("Play Selected", view)
      play_enter_action.shortcut = "Enter"
      play_enter_action.on_triggered do
        next unless view.has_focus? || view.viewport.has_focus?
        play_selected_playlist_row
      end
      view.add_action(play_enter_action)
      @play_queue_enter_action = play_enter_action

      delete_action = Qt6::Action.new("Remove from Queue", view)
      delete_action.shortcut = "Delete"
      delete_action.on_triggered do
        next unless view.has_focus? || view.viewport.has_focus?
        delete_selected_playlist_row
      end
      view.add_action(delete_action)
      @delete_queue_action = delete_action

      @playlist_model = model
      view
    end

    private def setup_queue_drop_target(view : Qt6::TreeView) : Nil
      viewport = view.viewport
      viewport.accept_drops = true

      filter = Qt6::EventFilter.new(viewport)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          mouse_event = event.mouse_event
          if mouse_event.button == 2
            show_queue_context_menu(view, viewport, mouse_event.position)
            true
          else
            index = view.index_at(mouse_event.position)
            begin
              @playlist_drag_source_row = index.valid? ? index.row : nil
            ensure
              index.release
            end
            @dragged_database_uris.clear
            @drag_source_type = :playlist
            false
          end
        when Qt6::EventType::MouseButtonDblClick
          play_selected_playlist_row
          true
        when Qt6::EventType::DragEnter
          @drag_source_type ||= :playlist
          @dragged_database_uris = selected_database_uris if @drag_source_type == :database
          false
        when Qt6::EventType::DragMove
          @playlist_drag_source_row = current_playlist_row(view).first?

          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          if drag_is_playlist_reorder?(drop_event)
            drop_event.accept_proposed_action
          elsif drag_is_database_drop?(drop_event)
            drop_event.accept_proposed_action
          end
          false
        when Qt6::EventType::DragLeave
          @playlist_drag_source_row = nil
          @drag_source_type = nil
          false
        when Qt6::EventType::Drop
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          handled = false
          if @drag_source_type == :playlist && drag_is_playlist_reorder?(drop_event)
            handled = move_selected_playlist_rows(queue_drop_row_for(drop_event))
          elsif @drag_source_type == :database && drag_is_database_drop?(drop_event)
            handled = append_selected_database_to_queue(queue_drop_row_for(drop_event))
          end

          if handled
            drop_event.accept_proposed_action
          else
            drop_event.ignore
          end

          @playlist_drag_source_row = nil
          @drag_source_type = nil
          true
        else
          false
        end
      end

      viewport.install_event_filter(filter)
      @queue_drop_filter = filter
    end

    private def show_queue_context_menu(view : Qt6::TreeView, viewport : Qt6::Widget, position : Qt6::PointF) : Nil
      index = view.index_at(position)
      begin
        return unless index.valid?

        row = index.row
        unless selected_playlist_rows(view).includes?(row)
          select_playlist_row(row)
        end

        @queue_play_now_action.try(&.enabled = selected_playlist_rows(view).size == 1)
        @queue_context_menu.try(&.exec_at(viewport, position))
      ensure
        index.release
      end
    end

    private def drag_is_playlist_reorder?(event : Qt6::DropEvent) : Bool
      model = @playlist_model
      row = @playlist_drag_source_row
      @drag_source_type == :playlist && !!event.mime_data && !!model && !row.nil? && model.row_count > 1
    end

    private def drag_is_database_drop?(event : Qt6::DropEvent) : Bool
      @drag_source_type == :database && !!event.mime_data && @dragged_database_uris.any?
    end

    private def queue_drop_row_for(event : Qt6::DropEvent) : Int32
      view = @playlist_view
      model = @playlist_model
      return 0 unless view && model
      return 0 if model.row_count <= 0

      y = event.position.y
      return 0 if y <= 4.0

      index = view.index_at(event.position)
      unless index.valid?
        index.release
        return model.row_count
      end

      rect = view.visual_rect(index)
      row = index.row
      index.release

      y < rect.y + rect.height / 2.0 ? row : row + 1
    end

    private def move_selected_playlist_rows(insert_row : Int32) : Bool
      view = @playlist_view
      return false unless view

      selected_rows = selected_playlist_rows(view).select { |row| row >= 0 && row < @playlist_ids.size }.sort.uniq
      return false if selected_rows.empty?

      selected_ids = selected_rows.compact_map { |row| @playlist_ids[row]? }
      return false if selected_ids.empty?

      current_ids = @playlist_ids.dup
      remaining_ids = current_ids.reject { |id| selected_ids.includes?(id) }
      target_row = insert_row.clamp(0, current_ids.size)
      target_row -= selected_rows.count { |row| row < target_row }
      target_row = target_row.clamp(0, remaining_ids.size)

      desired_ids = remaining_ids.dup
      selected_ids.each_with_index do |id, offset|
        desired_ids.insert(target_row + offset, id)
      end
      return true if desired_ids == current_ids

      mpd_action do |client|
        client.with_command_list do
          desired_ids.each_with_index do |id, desired_index|
            current_index = current_ids.index(id)
            next unless current_index
            next if current_index == desired_index

            client.moveid(id, desired_index)
            moved_id = current_ids.delete_at(current_index)
            current_ids.insert(desired_index, moved_id)
          end
        end
      end

      @just_moved_pos = target_row
      set_status("Queue order updated")
      true
    rescue ex
      @title_label.try(&.text = "Error")
      @subtitle_label.try(&.text = (ex.message || ex.to_s))
      false
    end

    private def clear_queue : Nil
      mpd_action do |client|
        client.clear
      end
      set_status("Queue cleared")
    end

    private def refresh_playlist(songs : Array(Hash(String, String))? = nil, *, scroll_to_current : Bool = true) : Nil
      Log.info { "mpd_ui: Refreshing playlist view..." }
      view = @playlist_view
      model = @playlist_model
      return unless view && model

      unless songs
        client = @client
        return unless client

        songs = client.playlistinfo
      end
      return unless songs

      @syncing = true
      @playlist_positions.clear
      @playlist_ids.clear
      model.clear
      model.set_horizontal_header_label(0, "State")
      model.set_horizontal_header_label(1, "Track")
      model.set_horizontal_header_label(2, "Time")

      configure_playlist_header(view)

      songs.each_with_index do |song, row|
        pos = song["Pos"]?.try(&.to_i?) || row
        id = song["Id"]?.try(&.to_i?) || pos
        @playlist_positions << pos
        @playlist_ids << id

        indicator_icon = playlist_indicator_icon(pos)
        tooltip = song_tooltip(song)
        indicator_item = Qt6::StandardItem.new("")
        indicator_item.icon = indicator_icon.not_nil! if indicator_icon && !indicator_icon.not_nil!.null?
        indicator_item.set_data(tooltip, Qt6::ItemDataRole::ToolTip)

        title_item = Qt6::StandardItem.new(playlist_title(song))
        title_item.set_data(tooltip, Qt6::ItemDataRole::ToolTip)

        time_item = Qt6::StandardItem.new(playlist_duration(song))
        time_item.set_data(tooltip, Qt6::ItemDataRole::ToolTip)
        time_item.set_data((Qt6::AlignmentFlag::Right | Qt6::AlignmentFlag::VCenter).value, Qt6::ItemDataRole::TextAlignment)

        model.set_item(row, 0, indicator_item)
        model.set_item(row, 1, title_item)
        model.set_item(row, 2, time_item)
      end

      if @just_moved_pos && (row = @playlist_positions.index(@just_moved_pos))
        select_playlist_row(row)
        @just_moved_pos = nil
      elsif scroll_to_current
        scroll_playlist_to_current_song
      end
    ensure
      @syncing = false
    end

    private def configure_playlist_header(view : Qt6::TreeView) : Nil
      header = view.header
      header.stretch_last_section = false
      header.set_section_resize_mode(0, Qt6::HeaderResizeMode::Fixed)
      header.set_section_resize_mode(1, Qt6::HeaderResizeMode::Stretch)
      header.set_section_resize_mode(2, Qt6::HeaderResizeMode::Fixed)
      header.resize_section(0, 36)
      header.resize_section(2, 64)
    end

    private def sync_playlist_indicators(previous_song_pos : Int32? = nil) : Nil
      model = @playlist_model
      return unless model

      positions = [previous_song_pos, @current_song_pos].compact.uniq
      positions.each do |pos|
        row = @playlist_positions.index(pos)
        update_playlist_indicator(row) if row
      end
    end

    private def update_playlist_indicator(row : Int32) : Nil
      model = @playlist_model
      return unless model
      return if row < 0 || row >= model.row_count

      item = model.item(row, 0)
      return unless item

      pos = @playlist_positions[row]?
      icon = pos ? playlist_indicator_icon(pos) : nil
      item.icon = icon && !icon.null? ? icon : Qt6::QIcon.new
    end

    private def scroll_playlist_to_current_song : Nil
      view = @playlist_view
      current_song_pos = @current_song_pos
      return unless view && current_song_pos

      row = @playlist_positions.index(current_song_pos)
      return unless row

      select_playlist_row(row)
    end

    private def play_selected_playlist_row : Nil
      return if @syncing

      view = @playlist_view
      return unless view

      row = current_playlist_row(view).first? || -1
      return if row < 0

      pos = @playlist_positions[row]?
      return unless pos

      mpd_action { |c| c.play(pos) }
    end

    private def delete_selected_playlist_row : Nil
      return if @syncing

      view = @playlist_view
      return unless view

      positions = selected_playlist_positions(view)
      return if positions.empty?

      mpd_action do |client|
        client.with_command_list do
          positions.sort.reverse_each do |pos|
            client.delete(pos)
          end
        end
      end

      suffix = positions.size == 1 ? "song" : "songs"
      set_status("Removed #{positions.size} #{suffix} from Queue")
    end

    private def selected_playlist_positions(view : Qt6::TreeView) : Array(Int32)
      selected_playlist_rows(view).compact_map { |row| @playlist_positions[row]? }
    end

    private def selected_playlist_rows(view : Qt6::TreeView) : Array(Int32)
      model = @playlist_model
      selection_model = view.selection_model
      return current_playlist_row(view) unless model && selection_model

      rows = [] of Int32
      model.row_count.times do |row|
        index = model.index(row, 0)
        begin
          rows << row if selection_model.selected?(index)
        ensure
          index.release
        end
      end

      rows.empty? ? current_playlist_row(view) : rows
    end

    private def current_playlist_row(view : Qt6::TreeView) : Array(Int32)
      index = view.current_index
      begin
        index.valid? ? [index.row] : [] of Int32
      ensure
        index.release
      end
    end

    private def select_playlist_row(row : Int32) : Nil
      view = @playlist_view
      model = @playlist_model
      return unless view && model
      return if row < 0 || row >= model.row_count

      index = model.index(row, 1)
      begin
        if selection_model = view.selection_model
          selection_model.set_current_index(index, Qt6::SelectionFlag::ClearAndSelect | Qt6::SelectionFlag::Rows)
        else
          view.current_index = index
        end
        view.scroll_to(index, Qt6::ScrollHint::PositionAtCenter)
      ensure
        index.release
      end
    end

    private def playlist_indicator_icon(pos : Int32) : Qt6::QIcon?
      return nil unless pos == @current_song_pos

      case @state
      when "play"
        @play_icon
      when "pause"
        @pause_icon
      else
        @stop_icon
      end
    end
  end
end
