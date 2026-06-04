module MPDUI
  class PlaylistTreeDragDrop
    getter filter : Qt6::EventFilter?
    getter dragged_song_uris : Array(String) = [] of String

    property on_song_mouse_press : Proc(Qt6::PointF, Nil)?
    property on_song_drag_enter : Proc(Nil)?
    property on_song_drag_finished : Proc(Nil)?
    property on_move_songs : Proc(String, Array(Tuple(Int32, Int32)), Nil)?
    property on_external_song_drag : Proc(Nil)?
    property on_external_song_drop : Proc(String, Int32?, Bool)?

    @dragged_song_playlist_name : String?
    @dragged_song_positions : Array(Int32) = [] of Int32
    @pending_drag_position : Tuple(Float64, Float64)?
    @playlist_controller = PlaylistController.new

    def initialize(@view : Qt6::TreeView, @model : PlaylistsModel, @selection : PlaylistTreeSelection)
    end

    def install : Nil
      viewport = @view.viewport
      viewport.accept_drops = true

      event_filter = Qt6::EventFilter.new(viewport)
      event_filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          mouse_event = event.mouse_event
          if mouse_event.button == 2
            false
          else
            if @selection.song_index_at?(mouse_event.position)
              @pending_drag_position = {mouse_event.position.x, mouse_event.position.y}
              @on_song_mouse_press.try(&.call(mouse_event.position))
            end
            false
          end
        when Qt6::EventType::DragEnter
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          remember_pending_dragged_song
          if internal_song_drag?
            @on_song_drag_enter.try(&.call)
          elsif external_drop_target(drop_event.position)
            @on_external_song_drag.try(&.call)
            drop_event.drop_action = Qt6::DropAction::CopyAction
            drop_event.accept
          end
          false
        when Qt6::EventType::DragMove
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          if !internal_song_drag? && external_drop_target(drop_event.position)
            @on_external_song_drag.try(&.call)
            drop_event.drop_action = Qt6::DropAction::CopyAction
            drop_event.accept
          end
          false
        when Qt6::EventType::Drop
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          if internal_song_drag?
            drop_event.ignore unless handle_internal_song_drop(drop_event)
            @on_song_drag_finished.try(&.call)
            clear_dragged_song
            true
          elsif handle_external_song_drop(drop_event)
            @on_song_drag_finished.try(&.call)
            true
          else
            clear_dragged_song
            @on_song_drag_finished.try(&.call)
            false
          end
        when Qt6::EventType::MouseButtonRelease
          clear_dragged_song
          @on_song_drag_finished.try(&.call)
          false
        when Qt6::EventType::DragLeave
          false
        else
          false
        end
      end

      viewport.install_event_filter(event_filter)
      @filter = event_filter
    end

    def clear_dragged_song : Nil
      @dragged_song_playlist_name = nil
      @dragged_song_positions.clear
      @dragged_song_uris.clear
      @pending_drag_position = nil
    end

    private def remember_pending_dragged_song : Nil
      position = @pending_drag_position
      return unless position

      @pending_drag_position = nil
      remember_dragged_song(Qt6::PointF.new(position[0], position[1]))
    end

    private def remember_dragged_song(position : Qt6::PointF) : Nil
      index = @view.index_at(position)
      begin
        unless index.valid? && @selection.song_index?(index)
          clear_dragged_song
          return
        end

        playlist_name = @selection.playlist_name_for_index(index)
        song_position = @selection.song_position_for_index(index)
        song_uri = @selection.song_uri_for_index(index)
        unless playlist_name && song_position && song_uri
          clear_dragged_song
          return
        end

        name, positions, uris = @selection.drag_snapshot(index, playlist_name, song_position, song_uri)
        @dragged_song_playlist_name = name
        @dragged_song_positions = positions
        @dragged_song_uris = uris
      ensure
        index.release
      end
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
        plan = @playlist_controller.move_plan(@model.row_count(parent_index), target.insert_position, @dragged_song_positions)
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

    private def handle_external_song_drop(event : Qt6::DropEvent) : Bool
      target = external_drop_target(event.position)
      return false unless target

      callback = @on_external_song_drop
      return false unless callback
      return false unless callback.call(target.playlist_name, target.insert_position)

      event.drop_action = Qt6::DropAction::CopyAction
      event.accept
      true
    end

    private record SongDropTarget, playlist_name : String, insert_position : Int32
    private record ExternalDropTarget, playlist_name : String, insert_position : Int32?

    private def song_drop_target(position : Qt6::PointF) : SongDropTarget?
      index = @view.index_at(position)
      begin
        return unless index.valid? && @selection.song_index?(index)

        playlist_name = @selection.playlist_name_for_index(index)
        target_position = @selection.song_position_for_index(index)
        return unless playlist_name && target_position

        rect = @view.visual_rect(index)
        insert_position = position.y < rect.y + rect.height / 2.0 ? target_position : target_position + 1
        SongDropTarget.new(playlist_name, insert_position)
      ensure
        index.release
      end
    end

    private def playlist_drop_target(position : Qt6::PointF) : String?
      index = @view.index_at(position)
      begin
        return unless index.valid?

        @selection.playlist_name_for_index(index)
      ensure
        index.release
      end
    end

    private def external_drop_target(position : Qt6::PointF) : ExternalDropTarget?
      index = @view.index_at(position)
      begin
        return unless index.valid?

        playlist_name = @selection.playlist_name_for_index(index)
        return unless playlist_name

        if @selection.song_index?(index)
          target_position = @selection.song_position_for_index(index)
          return unless target_position

          rect = @view.visual_rect(index)
          insert_position = position.y < rect.y + rect.height / 2.0 ? target_position : target_position + 1
          ExternalDropTarget.new(playlist_name, insert_position)
        else
          ExternalDropTarget.new(playlist_name, nil)
        end
      ensure
        index.release
      end
    end

    private def parent_index_for_playlist(name : String) : Qt6::ModelIndex
      @model.index_for_playlist(name) || Qt6::ModelIndex.new
    end
  end
end
