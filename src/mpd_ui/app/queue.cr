module MPDUI
  module AppQueue
    private def build_playlist(parent : Qt6::Widget) : QueueView
      queue = QueueView.new(parent)
      queue.on_play_selected = -> { play_selected_playlist_row }
      queue.on_remove_selected = -> { delete_selected_playlist_row }
      queue.on_clear_queue = -> { clear_queue }
      queue.on_save_as_playlist = -> { save_queue_as_playlist }
      queue.playlist_names_provider = -> { @playlists_view.try(&.playlist_names) || [] of String }
      queue.on_add_selected_to_playlist = ->(name : String) { add_selected_queue_songs_to_stored_playlist_from_menu(name) }
      queue.on_scroll_to_current = -> { scroll_playlist_to_current_song }
      queue.on_mouse_press_row = ->(row : Int32?) {
        @drag_context.begin_queue_drag(row)
      }
      queue.on_drag_enter = ->(drop_event : Qt6::DropEvent) {
        @drag_context.assume_queue_drag

        if drag_is_playlist_reorder?(drop_event)
          drop_event.accept_proposed_action
        elsif drag_is_external_uri_drop?(drop_event)
          accept_external_uri_drop(drop_event)
        end
      }
      queue.on_drag_move = ->(drop_event : Qt6::DropEvent) {
        @drag_context.queue_source_row = queue.current_rows.first? if @drag_context.queue?

        if drag_is_playlist_reorder?(drop_event)
          drop_event.accept_proposed_action
        elsif drag_is_external_uri_drop?(drop_event)
          accept_external_uri_drop(drop_event)
        end
      }
      queue.on_drag_leave = -> {
        @drag_context.finish_drag
      }
      queue.on_drop = ->(drop_event : Qt6::DropEvent) {
        handled = false
        if @drag_context.queue? && drag_is_playlist_reorder?(drop_event)
          handled = move_selected_playlist_rows(queue.drop_row_for(drop_event))
        elsif external_uri_drag_source? && drag_is_external_uri_drop?(drop_event)
          accept_external_uri_drop(drop_event)
          handled = append_selected_database_to_queue(queue.drop_row_for(drop_event))
          @preserve_queue_scroll_once = true if handled
        end

        @drag_context.finish_drag
        handled
      }

      queue
    end

    private def setup_queue_drop_target(queue : QueueView) : Nil
      queue.install_drop_filter
      @queue_drop_filter = queue.drop_filter
    end

    private def drag_is_playlist_reorder?(event : Qt6::DropEvent) : Bool
      row = @drag_context.queue_source_row
      @drag_context.queue? && !row.nil? && @queue_controller.size > 1
    end

    private def drag_is_external_uri_drop?(event : Qt6::DropEvent) : Bool
      external_uri_drag_source?
    end

    private def external_uri_drag_source? : Bool
      @drag_context.external_uri_source?
    end

    private def accept_external_uri_drop(event : Qt6::DropEvent) : Nil
      if @drag_context.stored_playlist?
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
          @queue_commands.move_to_plan(client, plan)
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

      selected_row = queue.focused? ? queue.current_rows.first? : nil
      preserve_scroll = @preserve_queue_scroll_once
      scroll_value = preserve_scroll ? queue.scroll_value : nil
      @preserve_queue_scroll_once = false

      @syncing = true
      @queue_controller.replace(songs)

      queue.render(songs) { |pos| playlist_indicator_text(pos) }
      queue.scroll_value = scroll_value if scroll_value

      if row = @just_moved_pos
        queue.select_row(row)
        @just_moved_pos = nil
      elsif selected_row && selected_row < queue.row_count
        queue.select_row(selected_row, scroll: false)
      elsif scroll_to_current && !preserve_scroll
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

      row_ranges = queue.selected_row_ranges
      position_ranges = @queue_controller.position_ranges_for_row_ranges(row_ranges)
      return if position_ranges.empty?

      @preserve_queue_scroll_once = true
      selected_count = position_ranges.sum { |first, last| last - first + 1 }
      host = @settings.host
      port = @settings.port
      suffix = selected_count == 1 ? "song" : "songs"
      set_status("Removing #{selected_count} #{suffix} from Queue…")

      run_background(
        ->(_result : Nil) {
          set_status("Removed #{selected_count} #{suffix} from Queue")
        },
        ->(ex : Exception) {
          @title_label.try(&.text = "Error")
          @subtitle_label.try(&.text = (ex.message || ex.to_s))
          set_status("Failed to remove songs from Queue")
        }
      ) do
        with_mpd_client(host, port) do |client|
          @queue_commands.delete_position_ranges(client, position_ranges, @queue_controller.size)
        end
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
