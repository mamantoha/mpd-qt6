module MPDUI
  class QueueView
    getter view : Qt6::TreeView
    getter model : Qt6::StandardItemModel
    getter drop_filter : Qt6::EventFilter?

    property on_play_selected : Proc(Nil)?
    property on_remove_selected : Proc(Nil)?
    property on_context_menu_open : Proc(Int32, Nil)?
    property on_mouse_press_row : Proc(Int32?, Nil)?
    property on_drag_enter : Proc(Nil)?
    property on_drag_move : Proc(Qt6::DropEvent, Nil)?
    property on_drag_leave : Proc(Nil)?
    property on_drop : Proc(Qt6::DropEvent, Bool)?

    @context_menu : Qt6::Menu
    @play_now_action : Qt6::Action

    def initialize(parent : Qt6::Widget)
      @view = Qt6::TreeView.new(parent)
      @model = Qt6::StandardItemModel.new(@view)
      configure_model
      configure_view

      @context_menu = Qt6::Menu.new("Queue", @view)
      @play_now_action = add_context_action("Play Now", "media-playback-start") { @on_play_selected.try(&.call) }
      add_context_action("Remove from Queue", "edit-delete") { @on_remove_selected.try(&.call) }
      add_shortcut("Return") { @on_play_selected.try(&.call) }
      add_shortcut("Enter") { @on_play_selected.try(&.call) }
      add_shortcut("Delete") { @on_remove_selected.try(&.call) }
    end

    def install_drop_filter : Nil
      viewport = @view.viewport
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
            @on_mouse_press_row.try(&.call(row_at(mouse_event.position)))
            false
          end
        when Qt6::EventType::MouseButtonDblClick
          @on_play_selected.try(&.call)
          true
        when Qt6::EventType::DragEnter
          @on_drag_enter.try(&.call)
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
            drop_event.accept_proposed_action
          else
            drop_event.ignore
          end

          true
        else
          false
        end
      end

      viewport.install_event_filter(filter)
      @drop_filter = filter
    end

    def render(songs : Array(Song), & : Int32 -> Qt6::QIcon?) : Nil
      @model.clear
      configure_model
      configure_header

      songs.each_with_index do |song, row|
        pos = song.pos || row
        tooltip = song.tooltip_html

        indicator_item = Qt6::StandardItem.new("")
        configure_queue_item(indicator_item)
        icon = yield pos
        indicator_item.icon = icon.not_nil! if icon && !icon.not_nil!.null?
        indicator_item.set_data(tooltip, Qt6::ItemDataRole::ToolTip)

        title_item = Qt6::StandardItem.new(song.queue_title)
        configure_queue_item(title_item)
        title_item.set_data(tooltip, Qt6::ItemDataRole::ToolTip)

        time_item = Qt6::StandardItem.new(song.duration_label)
        configure_queue_item(time_item)
        time_item.set_data(tooltip, Qt6::ItemDataRole::ToolTip)
        time_item.set_data((Qt6::AlignmentFlag::Right | Qt6::AlignmentFlag::VCenter).value, Qt6::ItemDataRole::TextAlignment)

        @model.set_item(row, 0, indicator_item)
        @model.set_item(row, 1, title_item)
        @model.set_item(row, 2, time_item)
      end
    end

    def update_indicator(row : Int32, icon : Qt6::QIcon?) : Nil
      return if row < 0 || row >= @model.row_count

      item = @model.item(row, 0)
      return unless item

      item.icon = icon && !icon.null? ? icon : Qt6::QIcon.new
    end

    def selected_rows : Array(Int32)
      selection_model = @view.selection_model
      return current_rows unless selection_model

      rows = [] of Int32
      @model.row_count.times do |row|
        index = @model.index(row, 0)
        begin
          rows << row if selection_model.selected?(index)
        ensure
          index.release
        end
      end

      rows.empty? ? current_rows : rows
    end

    def current_rows : Array(Int32)
      index = @view.current_index
      begin
        index.valid? ? [index.row] : [] of Int32
      ensure
        index.release
      end
    end

    def select_row(row : Int32, *, scroll : Bool = true) : Nil
      return if row < 0 || row >= @model.row_count

      index = @model.index(row, 1)
      begin
        if selection_model = @view.selection_model
          selection_model.set_current_index(index, Qt6::SelectionFlag::ClearAndSelect | Qt6::SelectionFlag::Rows)
        else
          @view.current_index = index
        end
        @view.scroll_to(index, Qt6::ScrollHint::PositionAtCenter) if scroll
      ensure
        index.release
      end
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

    def row_count : Int32
      @model.row_count
    end

    def empty? : Bool
      row_count <= 0
    end

    private def configure_model : Nil
      @model.set_horizontal_header_label(0, "State")
      @model.set_horizontal_header_label(1, "Track")
      @model.set_horizontal_header_label(2, "Time")
    end

    private def configure_queue_item(item : Qt6::StandardItem) : Nil
      item.flags = Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable | Qt6::ItemFlag::DragEnabled
    end

    private def configure_view : Nil
      @view.model = @model
      @view.header_hidden = true
      @view.root_is_decorated = false
      @view.uniform_row_heights = true
      @view.alternating_row_colors = true
      @view.selection_mode = Qt6::ItemSelectionMode::ExtendedSelection
      @view.selection_behavior = Qt6::ItemSelectionBehavior::SelectRows
      @view.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      @view.drag_enabled = true
      @view.accept_drops = true
      @view.drag_drop_mode = Qt6::ItemViewDragDropMode::DragDrop
      @view.drag_drop_overwrite_mode = false
      @view.default_drop_action = Qt6::DropAction::MoveAction
      @view.drop_indicator_shown = true
      @view.minimum_height = 320
      @view.style_sheet = <<-CSS
        QTreeView {
          border: none;
        }
        QTreeView::item {
          padding: 3px 0px;
        }
        CSS

      @view.header.stretch_last_section = false
      configure_header
    end

    private def configure_header : Nil
      header = @view.header
      header.stretch_last_section = false
      header.set_section_resize_mode(0, Qt6::HeaderResizeMode::Fixed)
      header.set_section_resize_mode(1, Qt6::HeaderResizeMode::Stretch)
      header.set_section_resize_mode(2, Qt6::HeaderResizeMode::Fixed)
      header.resize_section(0, 36)
      header.resize_section(2, 64)
    end

    private def add_context_action(label : String, icon_name : String, &block : ->) : Qt6::Action
      action = Qt6::Action.new(label, @view)
      icon = Qt6::QIcon.from_theme(icon_name)
      action.icon = icon unless icon.null?
      action.on_triggered { block.call }
      @context_menu.add_action(action)
      action
    end

    private def add_shortcut(shortcut : String, &block : ->) : Qt6::Action
      action = Qt6::Action.new("Queue #{shortcut}", @view)
      action.shortcut = shortcut
      action.on_triggered do
        next unless @view.has_focus? || @view.viewport.has_focus?
        block.call
      end
      @view.add_action(action)
      action
    end

    private def show_context_menu(viewport : Qt6::Widget, position : Qt6::PointF) : Nil
      row = row_at(position)
      return unless row

      select_row(row) unless selected_rows.includes?(row)
      @on_context_menu_open.try(&.call(row))
      @play_now_action.enabled = selected_rows.size == 1
      @context_menu.exec_at(viewport, position)
    end
  end
end
