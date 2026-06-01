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
      queue.on_drag_enter = -> {
        @drag_source_type ||= :playlist
        case @drag_source_type
        when :database
          @dragged_database_uris = selected_database_uris
        when :stored_playlist
          @dragged_database_uris = selected_stored_playlist_song_uris
        end
      }
      queue.on_drag_move = ->(drop_event : Qt6::DropEvent) {
        @playlist_drag_source_row = queue.current_rows.first?

        if drag_is_playlist_reorder?(drop_event)
          drop_event.accept_proposed_action
        elsif drag_is_external_uri_drop?(drop_event)
          drop_event.drop_action = Qt6::DropAction::CopyAction
          drop_event.accept
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
          drop_event.drop_action = Qt6::DropAction::CopyAction
          drop_event.accept
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
      external_uri_drag_source? && !!event.mime_data && @dragged_database_uris.present?
    end

    private def external_uri_drag_source? : Bool
      @drag_source_type == :database || @drag_source_type == :stored_playlist
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
        started_at = Time.instant
        p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "reorder queue command list start", plan.desired_ids.size
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
        p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "reorder queue command list finished", plan.desired_ids.size, Time.instant - started_at
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

      started_at = Time.instant
      fetch_started_at = Time.instant
      p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "refresh_playlist start"
      unless songs
        client = @client
        return unless client

        songs = client.playlistinfo.try(&.map { |metadata| Song.from_mpd(metadata) })
      end
      return unless songs
      p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "refresh_playlist fetched/mapped", songs.size, Time.instant - fetch_started_at

      @syncing = true
      controller_started_at = Time.instant
      @queue_controller.replace(songs)
      p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "refresh_playlist controller replace", songs.size, Time.instant - controller_started_at

      render_started_at = Time.instant
      queue.render(songs) { |pos| playlist_indicator_text(pos) }
      p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "refresh_playlist queue.render", songs.size, Time.instant - render_started_at

      if row = @just_moved_pos
        select_started_at = Time.instant
        queue.select_row(row)
        p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "refresh_playlist select moved row", row, Time.instant - select_started_at
        @just_moved_pos = nil
      elsif scroll_to_current
        scroll_started_at = Time.instant
        scroll_playlist_to_current_song
        p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "refresh_playlist scroll current", Time.instant - scroll_started_at
      end
      p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "refresh_playlist total", songs.size, Time.instant - started_at
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

      selected_started_at = Time.instant
      selected_rows = queue.selected_rows
      p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "delete queue selected rows", selected_rows.size, Time.instant - selected_started_at

      positions_started_at = Time.instant
      positions = @queue_controller.positions_for_rows(selected_rows)
      p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "delete queue positions", positions.size, Time.instant - positions_started_at
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
        started_at = Time.instant
        p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "delete queue selection command list start", positions.size
        with_mpd_client(host, port) do |client|
          client.with_command_list do
            positions.each do |pos|
              client.delete(pos)
            end
          end
        end
        p! "mpd_ui debug time", Time.local.to_s("%H:%M:%S.%6N"), "delete queue selection command list finished", positions.size, Time.instant - started_at
        nil
      end
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
