module MPDUI
  class PlaylistsView
    getter root : Qt6::Widget
    getter playlist_list : Qt6::ListWidget
    getter song_view : Qt6::TreeView
    getter song_model : Qt6::StandardItemModel
    getter context_filter : Qt6::EventFilter?

    property on_refresh : Proc(Nil)?
    property on_load : Proc(Nil)?
    property on_rename : Proc(Nil)?
    property on_delete : Proc(Nil)?
    property on_selection_changed : Proc(String?, Nil)?

    @playlists : Array(PlaylistEntry) = [] of PlaylistEntry
    @context_menu : Qt6::Menu
    @load_action : Qt6::Action
    @rename_action : Qt6::Action
    @delete_action : Qt6::Action

    def initialize(parent : Qt6::Widget)
      @root = Qt6::Widget.new(parent)
      @playlist_list = Qt6::ListWidget.new(@root)
      @song_view = Qt6::TreeView.new(@root)
      @song_model = Qt6::StandardItemModel.new(@song_view)
      configure_playlist_list
      configure_song_view

      @context_menu = Qt6::Menu.new("Playlist", @playlist_list)
      add_context_action("Refresh", "view-refresh") { @on_refresh.try(&.call) }
      @context_menu.add_separator
      @load_action = add_context_action("Load", "media-playback-start") { @on_load.try(&.call) }
      @rename_action = add_context_action("Rename", "edit-rename") { @on_rename.try(&.call) }
      @delete_action = add_context_action("Delete", "edit-delete") { @on_delete.try(&.call) }
      update_action_buttons

      @playlist_list.on_current_row_changed do |_row|
        update_action_buttons
        @on_selection_changed.try(&.call(selected_playlist_name))
      end
      @playlist_list.on_item_double_clicked { |_item| @on_load.try(&.call) }
      install_context_filter

      browser = Qt6::Splitter.new(Qt6::Orientation::Horizontal, @root)
      browser.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Expanding)
      browser << @playlist_list
      browser << @song_view

      @root.vbox do |column|
        column.spacing = 0
        column.set_contents_margins(0, 0, 0, 0)
        column << browser
      end
    end

    def render_playlists(playlists : Array(PlaylistEntry)) : Nil
      previous_name = selected_playlist_name
      @playlists = playlists
      @playlist_list.clear

      playlist_icon = Qt6::QIcon.from_theme("view-media-playlist")
      @playlists.each do |playlist|
        item =
          if playlist_icon.null?
            Qt6::ListWidgetItem.new(playlist.name)
          else
            Qt6::ListWidgetItem.new(playlist_icon, playlist.name)
          end
        item.tool_tip = playlist.tooltip
        @playlist_list.add_item(item)
      end

      selected_index = previous_name ? @playlists.index { |playlist| playlist.name == previous_name } : nil
      if selected_index
        @playlist_list.current_row = selected_index
      elsif @playlists.empty?
        render_message("No stored playlists")
      else
        @playlist_list.current_row = 0
      end

      update_action_buttons
    end

    def render_songs(songs : Array(Song)) : Nil
      @song_model.clear
      configure_song_model
      configure_song_header

      if songs.empty?
        render_message("Playlist is empty")
        return
      end

      songs.each_with_index do |song, row|
        title_item = Qt6::StandardItem.new(song.queue_title)
        configure_song_item(title_item)
        title_item.set_data(song.tooltip_html, Qt6::ItemDataRole::ToolTip)

        time_item = Qt6::StandardItem.new(song.duration_label)
        configure_song_item(time_item)
        time_item.set_data(song.tooltip_html, Qt6::ItemDataRole::ToolTip)
        time_item.set_data((Qt6::AlignmentFlag::Right | Qt6::AlignmentFlag::VCenter).value, Qt6::ItemDataRole::TextAlignment)

        @song_model.set_item(row, 0, title_item)
        @song_model.set_item(row, 1, time_item)
      end
    end

    def render_message(message : String) : Nil
      @song_model.clear
      configure_song_model
      @song_model << Qt6::StandardItem.new(message)
    end

    def selected_playlist_name : String?
      row = @playlist_list.current_row
      return if row < 0 || row >= @playlists.size

      @playlists[row].name
    end

    private def configure_playlist_list : Nil
      @playlist_list.minimum_width = 160
      @playlist_list.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Expanding)
      @playlist_list.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      @playlist_list.alternating_row_colors = true
      @playlist_list.spacing = 1
    end

    private def configure_song_view : Nil
      configure_song_model
      @song_view.model = @song_model
      @song_view.header_hidden = true
      @song_view.root_is_decorated = false
      @song_view.uniform_row_heights = true
      @song_view.alternating_row_colors = true
      @song_view.selection_behavior = Qt6::ItemSelectionBehavior::SelectRows
      @song_view.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      @song_view.minimum_width = 220
      @song_view.style_sheet = <<-CSS
        QTreeView {
          border: none;
        }
        QTreeView::item {
          padding: 3px 0px;
        }
        CSS
      configure_song_header
    end

    private def configure_song_model : Nil
      @song_model.set_horizontal_header_label(0, "Track")
      @song_model.set_horizontal_header_label(1, "Time")
    end

    private def configure_song_header : Nil
      header = @song_view.header
      header.stretch_last_section = false
      header.set_section_resize_mode(0, Qt6::HeaderResizeMode::Stretch)
      header.set_section_resize_mode(1, Qt6::HeaderResizeMode::Fixed)
      header.resize_section(1, 64)
    end

    private def configure_song_item(item : Qt6::StandardItem) : Nil
      item.flags = Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable
    end

    private def update_action_buttons : Nil
      enabled = !!selected_playlist_name
      @load_action.enabled = enabled
      @rename_action.enabled = enabled
      @delete_action.enabled = enabled
    end

    private def install_context_filter : Nil
      viewport = @playlist_list.viewport
      filter = Qt6::EventFilter.new(viewport)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonPress
          mouse_event = event.mouse_event
          if mouse_event.button == 2
            show_context_menu(viewport, mouse_event.position)
            true
          else
            false
          end
        else
          false
        end
      end

      viewport.install_event_filter(filter)
      @context_filter = filter
    end

    private def show_context_menu(viewport : Qt6::Widget, position : Qt6::PointF) : Nil
      row = row_at(position)
      @playlist_list.current_row = row if row
      update_action_buttons
      @context_menu.exec_at(viewport, position)
    end

    private def row_at(position : Qt6::PointF) : Int32?
      index = @playlist_list.index_at(position)
      begin
        index.valid? ? index.row : nil
      ensure
        index.release
      end
    end

    private def add_context_action(label : String, icon_name : String, &block : ->) : Qt6::Action
      action = Qt6::Action.new(label, @playlist_list)
      icon = Qt6::QIcon.from_theme(icon_name)
      action.icon = icon unless icon.null?
      action.on_triggered { block.call }
      @context_menu.add_action(action)
      action
    end

  end
end
