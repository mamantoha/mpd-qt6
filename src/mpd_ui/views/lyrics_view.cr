module MPDUI
  class LyricsView
    getter root : Qt6::Widget
    getter list_view : Qt6::ListView
    getter model : LyricsModel
    getter plain_text : Qt6::PlainTextEdit

    property on_seek : Proc(Int32, Nil)?

    @stack : Qt6::StackedWidget
    @message_text : Qt6::PlainTextEdit
    @context_menu : Qt6::Menu
    @copy_action : Qt6::Action
    @shortcuts : Array(Qt6::Shortcut) = [] of Qt6::Shortcut
    @result : LyricsResult?
    @synced_text : String = ""
    @plain_text_value : String = ""

    def initialize(parent : Qt6::Widget)
      @root = Qt6::Widget.new(parent)
      @stack = Qt6::StackedWidget.new(@root)
      @list_view = Qt6::ListView.new(@stack)
      @plain_text = Qt6::PlainTextEdit.new("", @stack)
      @message_text = Qt6::PlainTextEdit.new("", @stack)
      @model = LyricsModel.new(@list_view)

      configure_list_view
      configure_plain_text(@plain_text)
      configure_plain_text(@message_text)

      @stack << @message_text
      @stack << @list_view
      @stack << @plain_text

      @context_menu = Qt6::Menu.new("Lyrics", @root)
      @copy_action = Qt6::Action.new("Copy Lyrics", @root)
      copy_icon = Qt6::QIcon.from_theme("edit-copy")
      @copy_action.icon = copy_icon unless copy_icon.null?
      @copy_action.on_triggered { copy_lyrics }
      @context_menu.add_action(@copy_action)

      install_context_filter(@list_view.viewport)
      install_context_filter(@plain_text.viewport)
      install_context_filter(@message_text.viewport)
      add_shortcut("Ctrl+C") { copy_lyrics }

      @root.vbox do |column|
        column.spacing = 0
        column.set_contents_margins(0, 0, 0, 0)
        column << @stack
      end

      show_empty
    end

    def show_loading : Nil
      show_message("Loading lyrics...")
      scroll_to_top
    end

    def show_empty : Nil
      show_message("No lyrics loaded")
    end

    def show_not_found : Nil
      show_message("Lyrics not found")
    end

    def show_error(message : String) : Nil
      show_message(message.empty? ? "Failed to load lyrics" : message)
    end

    def show_disabled : Nil
      show_message("Online lyrics are disabled")
    end

    def render(result : LyricsResult) : Nil
      @result = result

      if result.synced?
        render_synced(result.synced_lines)
      elsif result.plain?
        render_plain(result.plain_text.to_s)
      elsif result.instrumental?
        show_message("Instrumental track")
      else
        show_not_found
      end
    end

    def sync_position(seconds : Float64, *, scroll : Bool = true) : Nil
      result = @result
      return reset_active_line unless result && result.synced?

      row = result.active_line_index(seconds.seconds)
      return if @model.active_row == row

      set_active_line(row, scroll: scroll)
    end

    def reset_active_line : Nil
      set_active_line(nil, scroll: false)
    end

    def set_active_line(row : Int32?, *, scroll : Bool = true) : Nil
      @model.active_row = row
      return unless scroll && row

      index = @model.index(row, 0)
      begin
        return unless index.valid?

        @list_view.current_index = index
        @list_view.scroll_to(index, Qt6::ScrollHint::PositionAtCenter)
      ensure
        index.release
      end
    end

    private def render_synced(lines : Array(LyricsLine)) : Nil
      @model.replace(lines)
      @synced_text = lines.map(&.text).join('\n')
      @plain_text_value = ""
      @stack.current_widget = @list_view
      scroll_to_top
      update_copy_action
    end

    private def render_plain(text : String) : Nil
      lines = text.each_line.map(&.strip).reject(&.empty?).map do |line|
        LyricsLine.new(0.seconds, line)
      end.to_a

      @model.replace(lines)
      @plain_text_value = text
      @synced_text = ""
      @stack.current_widget = @list_view
      scroll_to_top
      update_copy_action
    end

    private def show_message(message : String) : Nil
      @result = nil
      @model.clear
      @synced_text = ""
      @plain_text_value = ""
      @message_text.plain_text = message
      @stack.current_widget = @message_text
      update_copy_action
    end

    private def copy_lyrics : Nil
      text = lyrics_text
      return if text.empty?

      Qt6.clipboard.text = text
    end

    private def lyrics_text : String
      @plain_text_value.empty? ? @synced_text : @plain_text_value
    end

    private def update_copy_action : Nil
      @copy_action.enabled = !lyrics_text.empty?
    end

    private def scroll_to_top : Nil
      @list_view.scroll_to_top
    end

    private def configure_list_view : Nil
      @list_view.model = @model
      @list_view.selection_mode = Qt6::ItemSelectionMode::NoSelection
      @list_view.selection_behavior = Qt6::ItemSelectionBehavior::SelectRows
      @list_view.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      @list_view.uniform_item_sizes = false
      @list_view.word_wrap = true
      @list_view.spacing = 6
      palette = @list_view.palette
      begin
        @model.active_colors = {
          palette.color(Qt6::ColorRole::Highlight),
          palette.color(Qt6::ColorRole::HighlightedText),
        }
      ensure
        palette.release
      end
      @list_view.style_sheet = <<-CSS
        QListView {
          border: none;
        }
        QListView::item {
          padding: 6px 12px;
        }
        CSS
    end

    private def configure_plain_text(edit : Qt6::PlainTextEdit) : Nil
      edit.read_only = true
      edit.undo_redo_enabled = false
      edit.word_wrap_mode = Qt6::TextOptionWrapMode::WordWrap
      edit.style_sheet = <<-CSS
        QPlainTextEdit {
          border: none;
          padding: 8px;
        }
        CSS
    end

    private def install_context_filter(widget : Qt6::Widget) : Nil
      filter = Qt6::EventFilter.new(widget)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          mouse_event = event.mouse_event
          if mouse_event.button == 2
            @context_menu.exec_at(widget, mouse_event.position)
            true
          else
            false
          end
        when Qt6::EventType::MouseButtonDblClick
          handle_synced_line_double_click(event.mouse_event.position)
          true
        else
          false
        end
      end

      widget.install_event_filter(filter)
    end

    private def handle_synced_line_double_click(position : Qt6::PointF) : Nil
      result = @result
      return unless result && result.synced?

      index = @list_view.index_at(position)
      begin
        return unless index.valid?

        line = @model.line_at(index.row)
        return unless line

        @on_seek.try(&.call(line.time.total_seconds.to_i))
      ensure
        index.release
      end
    end

    private def add_shortcut(shortcut : String, &block : ->) : Qt6::Shortcut
      action = Qt6::Shortcut.new(shortcut, @root)
      action.context = Qt6::ShortcutContext::WidgetWithChildrenShortcut
      action.on_activated { block.call }
      @shortcuts << action
      action
    end
  end
end
