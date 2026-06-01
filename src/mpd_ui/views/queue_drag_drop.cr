module MPDUI
  class QueueDragDrop
    getter filter : Qt6::EventFilter?

    property on_context_menu : Proc(Qt6::Widget, Qt6::PointF, Nil)?
    property on_double_click_row : Proc(Int32?, Nil)?
    property on_mouse_press_row : Proc(Int32?, Nil)?
    property on_drag_enter : Proc(Qt6::DropEvent, Nil)?
    property on_drag_move : Proc(Qt6::DropEvent, Nil)?
    property on_drag_leave : Proc(Nil)?
    property on_drop : Proc(Qt6::DropEvent, Bool)?

    def initialize(@view : Qt6::TreeView, @model : QueueModel)
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
            @on_context_menu.try(&.call(viewport, mouse_event.position))
            true
          else
            @on_mouse_press_row.try(&.call(row_at(mouse_event.position)))
            false
          end
        when Qt6::EventType::MouseButtonDblClick
          mouse_event = event.mouse_event
          @on_double_click_row.try(&.call(row_at(mouse_event.position)))
          true
        when Qt6::EventType::DragEnter
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          @on_drag_enter.try(&.call(drop_event))
          false
        when Qt6::EventType::DragMove
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          @on_drag_move.try(&.call(drop_event))
          false
        when Qt6::EventType::DragLeave
          @on_drag_leave.try(&.call)
          false
        when Qt6::EventType::Drop
          drop_event = Qt6::DropEvent.new(event.to_unsafe)
          handled = @on_drop.try(&.call(drop_event)) || false

          if handled
            drop_event.accept_proposed_action unless drop_event.accepted?
          else
            drop_event.ignore
          end

          true
        else
          false
        end
      end

      viewport.install_event_filter(event_filter)
      @filter = event_filter
    end

    def drop_row_for(event : Qt6::DropEvent) : Int32
      return 0 if @model.row_count <= 0

      y = event.position.y
      return 0 if y <= 4.0

      index = @view.index_at(event.position)
      unless index.valid?
        index.release
        return @model.row_count
      end

      rect = @view.visual_rect(index)
      row = index.row
      index.release

      y < rect.y + rect.height / 2.0 ? row : row + 1
    end

    def row_at(position : Qt6::PointF) : Int32?
      index = @view.index_at(position)
      begin
        index.valid? ? index.row : nil
      ensure
        index.release
      end
    end
  end
end
