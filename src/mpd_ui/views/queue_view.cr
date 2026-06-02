module MPDUI
  class QueueView
    getter view : Qt6::TreeView
    getter model : QueueModel
    getter drop_filter : Qt6::EventFilter?

    property on_play_selected : Proc(Nil)?
    property on_remove_selected : Proc(Nil)?
    property on_clear_queue : Proc(Nil)?
    property on_save_as_playlist : Proc(Nil)?
    property on_scroll_to_current : Proc(Nil)?
    property on_context_menu_open : Proc(Int32, Nil)?
    property on_mouse_press_row : Proc(Int32?, Nil)?
    property on_drag_enter : Proc(Qt6::DropEvent, Nil)?
    property on_drag_move : Proc(Qt6::DropEvent, Nil)?
    property on_drag_leave : Proc(Nil)?
    property on_drop : Proc(Qt6::DropEvent, Bool)?

    @context_menu : Qt6::Menu
    @play_now_action : Qt6::Action
    @selection : QueueSelection
    @drag_drop : QueueDragDrop
    @shortcuts : Array(Qt6::Shortcut) = [] of Qt6::Shortcut

    def initialize(parent : Qt6::Widget)
      @view = Qt6::TreeView.new(parent)
      @model = QueueModel.new(@view)
      configure_view
      @selection = QueueSelection.new(@view)
      @drag_drop = QueueDragDrop.new(@view, @model)

      @context_menu = Qt6::Menu.new("Queue", @view)
      @play_now_action = add_context_action("Play Now", "media-playback-start") { @on_play_selected.try(&.call) }
      add_context_action("Remove from Queue", "edit-delete") { @on_remove_selected.try(&.call) }
      add_context_action("Clear Queue", "edit-clear") { @on_clear_queue.try(&.call) }
      @context_menu.add_separator
      add_context_action("Scroll to Current Song", "go-jump") { @on_scroll_to_current.try(&.call) }
      add_context_action("Save Queue as Playlist...", "document-save") { @on_save_as_playlist.try(&.call) }
      add_shortcut("Return") { @on_play_selected.try(&.call) }
      add_shortcut("Enter") { @on_play_selected.try(&.call) }
      add_shortcut("Delete") { @on_remove_selected.try(&.call) }
    end

    def install_drop_filter : Nil
      @drag_drop.on_context_menu = ->(viewport : Qt6::Widget, position : Qt6::PointF) { show_context_menu(viewport, position) }
      @drag_drop.on_double_click_row = ->(row : Int32?) {
        if row
          select_row(row, scroll: false)
          @on_play_selected.try(&.call)
        end
      }
      @drag_drop.on_mouse_press_row = ->(row : Int32?) { @on_mouse_press_row.try(&.call(row)) }
      @drag_drop.on_drag_enter = ->(event : Qt6::DropEvent) { @on_drag_enter.try(&.call(event)) }
      @drag_drop.on_drag_move = ->(event : Qt6::DropEvent) { @on_drag_move.try(&.call(event)) }
      @drag_drop.on_drag_leave = -> { @on_drag_leave.try(&.call) }
      @drag_drop.on_drop = ->(event : Qt6::DropEvent) { @on_drop.try(&.call(event)) || false }
      @drag_drop.install
      @drop_filter = @drag_drop.filter
    end

    def render(songs : Array(Song), &indicator_for : Int32 -> String) : Nil
      @model.replace(songs) { |pos| indicator_for.call(pos) }
      configure_header
    end

    def update_indicator(row : Int32, value : String) : Nil
      return if row < 0 || row >= @model.row_count

      @model.update_indicator(row, value)
    end

    def selected_rows : Array(Int32)
      @selection.selected_rows
    end

    def selected_row_ranges : Array(Tuple(Int32, Int32))
      @selection.selected_row_ranges
    end

    def selected_row_count : Int32
      @selection.selected_row_count
    end

    def selected_row?(row : Int32) : Bool
      @selection.selected_row?(row)
    end

    def current_rows : Array(Int32)
      @selection.current_rows
    end

    def focused? : Bool
      @view.has_focus? || @view.viewport.has_focus?
    end

    def scroll_value : Int32
      @view.vertical_scroll_bar.value
    end

    def scroll_value=(value : Int32) : Int32
      scrollbar = @view.vertical_scroll_bar
      scrollbar.value = Math.min(value, scrollbar.maximum)
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
      @drag_drop.drop_row_for(event)
    end

    def row_at(position : Qt6::PointF) : Int32?
      @drag_drop.row_at(position)
    end

    def row_count : Int32
      @model.row_count
    end

    def empty? : Bool
      row_count <= 0
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

    private def add_shortcut(shortcut : String, &block : ->) : Qt6::Shortcut
      action = Qt6::Shortcut.new(shortcut, @view)
      action.context = Qt6::ShortcutContext::WidgetWithChildrenShortcut
      action.on_activated do
        next unless @view.has_focus? || @view.viewport.has_focus?
        block.call
      end
      @shortcuts << action
      action
    end

    private def show_context_menu(viewport : Qt6::Widget, position : Qt6::PointF) : Nil
      row = row_at(position)
      return unless row

      select_row(row) unless selected_row?(row)
      @on_context_menu_open.try(&.call(row))
      @play_now_action.enabled = selected_row_count == 1
      @context_menu.exec_at(viewport, position)
    end
  end
end
