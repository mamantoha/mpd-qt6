module MPDUI
  class LibraryView
    getter root : Qt6::Widget
    getter tree : Qt6::TreeView
    getter model : LibraryModel
    getter search_panel : Qt6::Widget
    getter search_edit : Qt6::LineEdit
    getter genre_combo : Qt6::ComboBox
    getter escape_shortcut : Qt6::Shortcut
    getter drag_filter : Qt6::EventFilter?

    property on_search_changed : Proc(Nil)?
    property on_search_closed : Proc(Nil)?
    property on_genre_changed : Proc(Nil)?
    property on_add_to_queue : Proc(Nil)?
    property on_selection_changed : Proc(Nil)?
    property on_mouse_press : Proc(Nil)?
    property on_mouse_release : Proc(Nil)?
    property on_drag_enter : Proc(Nil)?
    property on_drag_finished : Proc(Nil)?

    @context_menu : Qt6::Menu
    @delegate : Qt6::StyledItemDelegate
    @updating_genres : Bool = false

    def initialize(parent : Qt6::Widget)
      @root = Qt6::Widget.new(parent)
      @search_panel = Qt6::Widget.new(@root)
      @search_panel.visible = false
      @search_edit = Qt6::LineEdit.new("", @search_panel)
      @search_edit.placeholder_text = "Search..."
      close_search_button = Qt6::PushButton.new("x", @search_panel)
      close_icon = Qt6::QIcon.from_theme("window-close")
      unless close_icon.null?
        close_search_button.icon = close_icon
        close_search_button.text = ""
      end
      close_search_button.fixed_width = 34
      close_search_button.tool_tip = "Close search"

      @tree = Qt6::TreeView.new(@root)
      @model = LibraryModel.new(@tree)
      configure_tree
      @genre_combo = Qt6::ComboBox.new(@root)
      @genre_combo.add_item("All Genres")
      @genre_combo.on_current_text_changed do |_text|
        @on_genre_changed.try(&.call) unless @updating_genres
      end

      @delegate = TwoLineItemDelegate.build(@tree, @model)
      @tree.item_delegate = @delegate
      @tree.on_current_index_changed { @on_selection_changed.try(&.call) }

      @context_menu = Qt6::Menu.new("Library", @tree)
      add_to_queue_action = Qt6::Action.new("Add to Queue", @tree)
      add_icon = Qt6::QIcon.from_theme("list-add")
      add_to_queue_action.icon = add_icon unless add_icon.null?
      add_to_queue_action.on_triggered { @on_add_to_queue.try(&.call) }
      @context_menu.add_action(add_to_queue_action)

      @search_edit.on_text_changed { |_text| @on_search_changed.try(&.call) }
      close_search_button.on_clicked { @on_search_closed.try(&.call) }
      @escape_shortcut = Qt6::Shortcut.new("Esc", @search_edit)
      @escape_shortcut.context = Qt6::ShortcutContext::WidgetShortcut
      @escape_shortcut.on_activated do
        @on_search_closed.try(&.call) if @search_edit.has_focus?
      end

      @search_panel.hbox do |row|
        row.spacing = 4
        row.set_contents_margins(4, 4, 4, 2)
        row << @search_edit
        row << close_search_button
      end

      @root.vbox do |column|
        column.spacing = 0
        column.set_contents_margins(0, 0, 0, 0)
        column << @search_panel
        column << @tree
        column << @genre_combo
      end
    end

    def install_drag_filter : Nil
      viewport = @tree.viewport
      filter = Qt6::EventFilter.new(viewport)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          mouse_event = event.mouse_event
          if mouse_event.button == 2
            show_context_menu(viewport, mouse_event.position)
            true
          else
            @on_mouse_press.try(&.call)
            false
          end
        when Qt6::EventType::DragEnter
          @on_drag_enter.try(&.call)
          false
        when Qt6::EventType::MouseButtonRelease
          @on_mouse_release.try(&.call)
          false
        when Qt6::EventType::Drop
          @on_drag_finished.try(&.call)
          false
        else
          false
        end
      end

      viewport.install_event_filter(filter)
      @drag_filter = filter
    end

    def query : String
      @search_edit.text.strip
    end

    def selected_genre : String?
      genre = @genre_combo.current_text.strip
      genre.empty? || genre == "All Genres" ? nil : genre
    end

    def render_genres(genres : Array(String)) : Nil
      selected = @genre_combo.current_text
      @updating_genres = true
      @genre_combo.clear
      @genre_combo.add_item("All Genres")
      genres.each { |genre| @genre_combo.add_item(genre) }
      index = @genre_combo.find_text(selected)
      @genre_combo.current_index = index >= 0 ? index : 0
    ensure
      @updating_genres = false
    end

    def show_search : Nil
      @search_panel.visible = true
      @search_edit.set_focus
      @search_edit.select_all
    end

    def hide_search : Nil
      @search_panel.visible = false
      @tree.set_focus
    end

    def clear_search : Nil
      @search_edit.clear
    end

    def search_empty? : Bool
      @search_edit.text.empty?
    end

    def show_message(message : String) : Nil
      @model.show_message(message)
    end

    def render(result : LibraryIndex::Result, *, expand_all : Bool = false) : Nil
      @model.replace(result)
      @tree.expand_all if expand_all
    end

    def selected_uris : Array(String)
      if selection_model = @tree.selection_model
        selected_indexes = selection_model.selected_rows(0)
        uris = @model.uris_for_indexes(selected_indexes, selection_model)

        selected_indexes.each(&.release)
        unless uris.empty?
          return uris
        end
      end

      index = @tree.current_index
      return [] of String unless index.valid?

      @model.uris_for_index(index)
    end

    def drag_uris : Array(String)
      @model.drag_uris
    end

    def clear_drag_uris : Nil
      @model.drag_uris.clear
    end

    private def configure_tree : Nil
      configure_model
      @tree.model = @model
      @tree.header_hidden = true
      @tree.header.stretch_last_section = true
      @tree.header.set_section_resize_mode(0, Qt6::HeaderResizeMode::Stretch)
      @tree.root_is_decorated = true
      @tree.uniform_row_heights = false
      @tree.icon_size = Qt6::Size.new(24, 24)
      @tree.selection_mode = Qt6::ItemSelectionMode::ExtendedSelection
      @tree.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      @tree.alternating_row_colors = true
      @tree.drag_enabled = true
      @tree.drag_drop_mode = Qt6::ItemViewDragDropMode::DragOnly
      @tree.default_drop_action = Qt6::DropAction::CopyAction
      @tree.drop_indicator_shown = true
      @tree.minimum_height = 320
      @tree.style_sheet = <<-CSS
        QTreeView {
          border: none;
        }
        QTreeView::item {
          padding: 0px;
        }
        CSS
    end

    private def show_context_menu(viewport : Qt6::Widget, position : Qt6::PointF) : Nil
      index = @tree.index_at(position)
      begin
        return unless index.valid?

        selection_model = @tree.selection_model
        unless selection_model && selection_model.selected?(index)
          selection_model.try(&.set_current_index(index, Qt6::SelectionFlag::ClearAndSelect))
          @tree.current_index = index
        end

        @context_menu.exec_at(viewport, position)
      ensure
        index.release
      end
    end

    private def configure_model : Nil
    end
  end
end
