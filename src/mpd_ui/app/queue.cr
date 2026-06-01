module MPDUI
  module AppQueue
    private def build_playlist(parent : Qt6::Widget) : QueueView
      queue = QueueView.new(parent)
      queue.on_play_selected = -> { play_selected_playlist_row }
      queue.on_remove_selected = -> { delete_selected_playlist_row }
      queue.on_save_as_playlist = -> { save_queue_as_playlist }
      queue.on_mouse_press_row = ->(row : Int32?) {
        @playlist_drag_source_row = row
        @dragged_database_uris.clear
        @drag_source_type = :playlist
      }
      queue.on_drag_enter = ->(drop_event : Qt6::DropEvent) {
        @drag_source_type ||= :playlist

        if drag_is_playlist_reorder?(drop_event)
          drop_event.accept_proposed_action
        elsif drag_is_external_uri_drop?(drop_event)
          accept_external_uri_drop(drop_event)
        end
      }
      queue.on_drag_move = ->(drop_event : Qt6::DropEvent) {
        @playlist_drag_source_row = queue.current_rows.first?

        if drag_is_playlist_reorder?(drop_event)
          drop_event.accept_proposed_action
        elsif drag_is_external_uri_drop?(drop_event)
          accept_external_uri_drop(drop_event)
        end
      }
      queue.on_drag_leave = -> {
        @playlist_drag_source_row = nil
        @drag_source_type = nil
      }
      queue.on_drop = ->(drop_event : Qt6::DropEvent) {
        handled = false
        if @drag_source_type == :playlist && drag_is_playlist_reorder?(drop_event)
          handled = move_selected_playlist_rows(queue.drop_row_for(drop_event))
        elsif external_uri_drag_source? && drag_is_external_uri_drop?(drop_event)
          accept_external_uri_drop(drop_event)
          handled = append_selected_database_to_queue(queue.drop_row_for(drop_event))
        end

        @playlist_drag_source_row = nil
        @drag_source_type = nil
        handled
      }

      queue
    end

    private def setup_queue_drop_target(queue : QueueView) : Nil
      queue.install_drop_filter
      @queue_drop_filter = queue.drop_filter
    end

    private def drag_is_playlist_reorder?(event : Qt6::DropEvent) : Bool
      row = @playlist_drag_source_row
      @drag_source_type == :playlist && !!event.mime_data && !row.nil? && @queue_controller.size > 1
    end

    private def drag_is_external_uri_drop?(event : Qt6::DropEvent) : Bool
      external_uri_drag_source? && !!event.mime_data
    end

    private def external_uri_drag_source? : Bool
      @drag_source_type == :database || @drag_source_type == :stored_playlist
    end

    private def accept_external_uri_drop(event : Qt6::DropEvent) : Nil
      if @drag_source_type == :stored_playlist
        event.drop_action = Qt6::DropAction::CopyAction
        event.accept
      else
        event.accept_proposed_action
      end
    end

    private def move_selected_playlist_rows(insert_row : Int32) : Bool
      queue = @queue_view
      return false unless queue

      plan = @queue_controller.move_plan(insert_row, queue.selected_rows)
      return false unless plan

      current_ids = plan.current_ids
      host = @settings.host
      port = @settings.port
      set_status("Updating queue order…")

      run_background(
        ->(_result : Nil) {
          @just_moved_pos = plan.target_row
          set_status("Queue order updated")
        },
        ->(ex : Exception) {
          @title_label.try(&.text = "Error")
          @subtitle_label.try(&.text = (ex.message || ex.to_s))
          set_status("Failed to update queue order")
        }
      ) do
        with_mpd_client(host, port) do |client|
          client.with_command_list do
            plan.desired_ids.each_with_index do |id, desired_index|
              current_index = current_ids.index(id)
              next unless current_index
              next if current_index == desired_index

              client.moveid(id, desired_index)
              moved_id = current_ids.delete_at(current_index)
              current_ids.insert(desired_index, moved_id)
            end
          end
        end
        nil
      end

      true
    end

    private def clear_queue : Nil
      mpd_action do |client|
        client.clear
      end
      set_status("Queue cleared")
    end

    private def refresh_playlist(songs : Array(Song)? = nil, *, scroll_to_current : Bool = true) : Nil
      Log.info { "mpd_ui: Refreshing playlist view..." }
      queue = @queue_view
      return unless queue

      unless songs
        client = @client
        return unless client

        songs = client.playlistinfo.try(&.map { |metadata| Song.from_mpd(metadata) })
      end
      return unless songs

      @syncing = true
      @queue_controller.replace(songs)

      queue.render(songs) { |pos| playlist_indicator_text(pos) }

      if row = @just_moved_pos
        queue.select_row(row)
        @just_moved_pos = nil
      elsif scroll_to_current
        scroll_playlist_to_current_song
      end
    ensure
      @syncing = false
    end

    private def sync_playlist_indicators(previous_song_pos : Int32? = nil) : Nil
      positions = [previous_song_pos, @playback_state.song_position].compact.uniq!
      positions.each do |pos|
        row = @queue_controller.row_for_position(pos)
        update_playlist_indicator(row) if row
      end
    end

    private def update_playlist_indicator(row : Int32) : Nil
      pos = @queue_controller.position_at(row)
      indicator = pos ? playlist_indicator_text(pos) : ""
      @queue_view.try(&.update_indicator(row, indicator))
    end

    private def scroll_playlist_to_current_song : Nil
      queue = @queue_view
      current_song_pos = @playback_state.song_position
      return unless queue && current_song_pos

      row = @queue_controller.row_for_position(current_song_pos)
      return unless row

      queue.select_row(row)
    end

    private def play_selected_playlist_row : Nil
      return if @syncing

      queue = @queue_view
      return unless queue

      row = queue.current_rows.first? || -1
      return if row < 0

      pos = @queue_controller.position_at(row)
      return unless pos

      mpd_action(&.play(pos))
    end

    private def delete_selected_playlist_row : Nil
      return if @syncing

      queue = @queue_view
      return unless queue

      selected_rows = queue.selected_rows

      positions = @queue_controller.positions_for_rows(selected_rows)
      return if positions.empty?

      positions = positions.sort.reverse
      host = @settings.host
      port = @settings.port
      suffix = positions.size == 1 ? "song" : "songs"
      set_status("Removing #{positions.size} #{suffix} from Queue…")

      run_background(
        ->(_result : Nil) {
          set_status("Removed #{positions.size} #{suffix} from Queue")
        },
        ->(ex : Exception) {
          @title_label.try(&.text = "Error")
          @subtitle_label.try(&.text = (ex.message || ex.to_s))
          set_status("Failed to remove songs from Queue")
        }
      ) do
        with_mpd_client(host, port) do |client|
          delete_queue_positions(client, positions)
        end
        nil
      end
    end

    private def delete_queue_positions(client : MPD::Client, positions : Array(Int32)) : Nil
      if positions.size >= @queue_controller.size
        client.clear
        return
      end

      ranges = queue_delete_ranges(positions)
      client.with_command_list do
        ranges.reverse_each do |first, last|
          if first == last
            client.delete(first)
          else
            client.delete(first..last)
          end
        end
      end
    end

    private def queue_delete_ranges(positions : Array(Int32)) : Array(Tuple(Int32, Int32))
      sorted = positions.sort.uniq!
      return [] of Tuple(Int32, Int32) if sorted.empty?

      ranges = [] of Tuple(Int32, Int32)
      first = sorted.first
      last = first

      sorted[1..].each do |position|
        if position == last + 1
          last = position
        else
          ranges << {first, last}
          first = position
          last = position
        end
      end

      ranges << {first, last}
      ranges
    end

    private def select_playlist_row(row : Int32) : Nil
      @queue_view.try(&.select_row(row))
    end

    private def playlist_indicator_text(pos : Int32) : String
      playback = @playback_state
      return "" unless pos == playback.song_position

      if playback.playing?
        "▶"
      elsif playback.paused?
        "Ⅱ"
      else
        "■"
      end
    end
  end
end
