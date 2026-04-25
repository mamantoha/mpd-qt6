module MPDUI
  module AppQueue
    private def build_playlist(parent : Qt6::Widget) : Qt6::TableWidget
      table = Qt6::TableWidget.new(parent)
      table.column_count = 3
      table.row_count = 0
      table.set_horizontal_header_label(0, "")
      table.set_horizontal_header_label(1, "Track")
      table.set_horizontal_header_label(2, "Time")
      table.alternating_row_colors = true
      table.selection_mode = Qt6::ItemSelectionMode::ExtendedSelection
      table.selection_behavior = Qt6::ItemSelectionBehavior::SelectRows
      table.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      table.show_grid = false
      table.drag_enabled = true
      table.accept_drops = true
      table.drag_drop_mode = Qt6::ItemViewDragDropMode::DragDrop
      table.drag_drop_overwrite_mode = false
      table.default_drop_action = Qt6::DropAction::MoveAction
      table.drop_indicator_shown = true
      table.minimum_height = 320

      table.horizontal_header.fixed_height = 0
      table.horizontal_header.set_section_resize_mode(0, Qt6::HeaderResizeMode::ResizeToContents)
      table.horizontal_header.set_section_resize_mode(1, Qt6::HeaderResizeMode::Stretch)
      table.horizontal_header.set_section_resize_mode(2, Qt6::HeaderResizeMode::ResizeToContents)
      table.vertical_header.fixed_width = 0

      table.on_item_double_clicked do |_item|
        play_selected_playlist_row
      end

      delete_action = Qt6::Action.new("Remove from Queue", table)
      delete_action.shortcut = "Delete"
      delete_action.on_triggered do
        next unless table.has_focus? || table.viewport.has_focus?
        delete_selected_playlist_row
      end
      table.add_action(delete_action)
      @delete_queue_action = delete_action

      table
    end

    private def setup_queue_drop_target(table : Qt6::TableWidget) : Nil
      viewport = table.viewport
      viewport.accept_drops = true

      filter = Qt6::EventFilter.new(viewport)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          row = table.current_row
          @playlist_drag_source_row = row >= 0 ? row : nil
          @dragged_database_uris.clear
          @drag_source_type = :playlist
          false
        when Qt6::EventType::DragEnter
          @drag_source_type ||= :playlist
          false
        when Qt6::EventType::DragMove
          row = table.current_row
          @playlist_drag_source_row = row >= 0 ? row : nil

          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          if drag_is_playlist_reorder?(drop_event)
            drop_event.accept_proposed_action
          elsif drag_is_database_drop?(drop_event)
            @dragged_database_uris = selected_database_uris if selected_database_uris.any?
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
            handled = move_playlist_row(@playlist_drag_source_row.not_nil!, queue_drop_row_for(drop_event))
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

    private def drag_is_playlist_reorder?(event : Qt6::DropEvent) : Bool
      table = @playlist_table
      row = @playlist_drag_source_row
      @drag_source_type == :playlist && !!event.mime_data && !!table && !row.nil? && table.row_count > 1
    end

    private def drag_is_database_drop?(event : Qt6::DropEvent) : Bool
      @drag_source_type == :database && !!event.mime_data && (@dragged_database_uris.any? || selected_database_uris.any?)
    end

    private def queue_drop_row_for(event : Qt6::DropEvent) : Int32
      table = @playlist_table
      return 0 unless table
      return 0 if table.row_count <= 0

      y = event.position.y
      return 0 if y <= 4.0

      index = table.index_at(event.position)
      unless index.valid?
        index.release
        return table.row_count
      end

      rect = table.visual_rect(index)
      row = index.row
      index.release

      y < rect.y + rect.height / 2.0 ? row : row + 1
    end

    private def move_playlist_row(source_row : Int32, insert_row : Int32) : Bool
      source_pos = @playlist_positions[source_row]?
      return false unless source_pos

      target_row = insert_row.clamp(0, @playlist_positions.size)
      target_row -= 1 if target_row > source_row
      return true if target_row == source_row

      mpd_action do |client|
        client.move(source_pos, target_row)
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

    private def refresh_playlist(*, song_changed : Bool = false) : Nil
      client = @client
      table = @playlist_table
      return unless client && table

      songs = client.playlistinfo
      return unless songs

      flags = Qt6::ItemFlag::Selectable | Qt6::ItemFlag::Enabled | Qt6::ItemFlag::DragEnabled

      @syncing = true
      @playlist_positions.clear
      table.clear_contents
      table.row_count = songs.size

      songs.each_with_index do |song, row|
        pos = song["Pos"]?.try(&.to_i?) || row
        @playlist_positions << pos

        indicator_icon = playlist_indicator_icon(pos)
        indicator_item = Qt6::TableWidgetItem.new("")
        indicator_item.flags = flags
        indicator_item.icon = indicator_icon.not_nil! if indicator_icon && !indicator_icon.not_nil!.null?

        title_item = Qt6::TableWidgetItem.new(playlist_title(song))
        title_item.flags = flags

        time_item = Qt6::TableWidgetItem.new(playlist_duration(song))
        time_item.flags = flags

        table.set_item(row, 0, indicator_item)
        table.set_item(row, 1, title_item)
        table.set_item(row, 2, time_item)
      end

      if @just_moved_pos && (row = @playlist_positions.index(@just_moved_pos))
        table.set_current_cell(row, 1)
        @just_moved_pos = nil
      elsif song_changed
        scroll_playlist_to_current_song
      end
    ensure
      @syncing = false
    end

    private def scroll_playlist_to_current_song : Nil
      table = @playlist_table
      current_song_pos = @current_song_pos
      return unless table && current_song_pos

      row = @playlist_positions.index(current_song_pos)
      return unless row

      table.set_current_cell(row, 1)
    end

    private def play_selected_playlist_row : Nil
      return if @syncing

      table = @playlist_table
      return unless table

      row = table.current_row
      return if row < 0

      pos = @playlist_positions[row]?
      return unless pos

      mpd_action { |c| c.play(pos) }
    end

    private def delete_selected_playlist_row : Nil
      return if @syncing

      table = @playlist_table
      return unless table

      positions = selected_playlist_positions(table)
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

    private def selected_playlist_positions(table : Qt6::TableWidget) : Array(Int32)
      selected_playlist_rows(table).compact_map { |row| @playlist_positions[row]? }
    end

    private def selected_playlist_rows(table : Qt6::TableWidget) : Array(Int32)
      model = table.model
      selection_model = table.selection_model
      return current_playlist_row(table) unless model && selection_model

      rows = [] of Int32
      table.row_count.times do |row|
        index = model.index(row, 0)
        begin
          rows << row if selection_model.selected?(index)
        ensure
          index.release
        end
      end

      rows.empty? ? current_playlist_row(table) : rows
    end

    private def current_playlist_row(table : Qt6::TableWidget) : Array(Int32)
      row = table.current_row
      row >= 0 ? [row] : [] of Int32
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
