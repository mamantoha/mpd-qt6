module MPDUI
  class LibraryView
    getter root : Qt6::Widget
    getter tree : Qt6::TreeView
    getter model : Qt6::StandardItemModel
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
      @model = Qt6::StandardItemModel.new(@tree)
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
      @model.clear
      configure_model
      @model << Qt6::StandardItem.new(message)
    end

    def render(result : LibraryIndex::Result, *, expand_all : Bool = false) : Nil
      @model.clear
      configure_model

      if result.artists.empty?
        @model << item(result.filtered ? "No matching songs" : "Database is empty")
        return
      end

      artist_icon = themed_icon("user-identiry", "person.circle")
      album_icon = themed_icon("media-optical-audio", "media-optical")
      song_icon = themed_icon("audio-x-generic", "music.note.list")

      result.artists.each do |artist|
        artist_item = item(artist.name, artist.summary)
        artist_item.icon = artist_icon unless artist_icon.null?

        artist.albums.each do |album|
          album_item = item(album.title, album.summary)
          album_item.icon = album_icon unless album_icon.null?

          album.songs.each do |song|
            song_item = item(song_title(song), song.duration_label, song.file)
            song_item.icon = song_icon unless song_icon.null?
            song_item.set_data(song.tooltip_html, Qt6::ItemDataRole::ToolTip)
            album_item << song_item
          end

          artist_item << album_item
        end

        @model << artist_item
      end

      @tree.expand_all if expand_all
    end

    def selected_uris : Array(String)
      if selection_model = @tree.selection_model
        uris = [] of String
        selected_indexes = selection_model.selected_indexes

        selected_indexes.each do |index|
          begin
            next unless index.valid?
            next unless index.column == 0

            if item = @model.item_from_index(index)
              collect_uris(item, uris)
            end
          ensure
            index.release
          end
        end

        uris.uniq!
        unless uris.empty?
          return uris
        end
      end

      index = @tree.current_index
      return [] of String unless index.valid?

      root_item = @model.item_from_index(index)
      return [] of String unless root_item

      uris = [] of String
      collect_uris(root_item, uris)
      uris.uniq!
      uris
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

    private def configure_model : Nil
      @model.set_horizontal_header_label(0, "Database")
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

    private def collect_uris(item : Qt6::StandardItem, uris : Array(String)) : Nil
      if file = item.data(Qt6::ItemDataRole::User).as?(String)
        uris << file unless file.empty?
      end

      item.row_count.times do |row|
        child = item.child(row)
        collect_uris(child, uris) if child
      end
    end

    private def item(title : String, subtitle : String? = nil, file : String? = nil) : Qt6::StandardItem
      item = TwoLineItemDelegate.item(title, subtitle)
      item.set_data(file, Qt6::ItemDataRole::User) if file
      item
    end

    private def song_title(song : Song) : String
      song.database_label.split(" • ", 2).first
    end

    private def themed_icon(*names : String) : Qt6::QIcon
      names.each do |name|
        icon = Qt6::QIcon.from_theme(name)
        return icon unless icon.null?
      end

      Qt6::QIcon.new
    end
  end
end
