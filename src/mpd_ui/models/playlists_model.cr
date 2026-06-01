module MPDUI
  class PlaylistsModel < Qt6::AbstractTreeModel
    MIME_TYPE = "application/x-garnetune-stored-playlist-song"

    ROW_TYPE_MESSAGE  = "message"
    ROW_TYPE_PLAYLIST = "playlist"
    ROW_TYPE_SONG     = "song"

    private class Node
      getter id : UInt64
      property parent_id : UInt64?
      property row : Int32
      getter row_type : String
      getter title : String
      getter subtitle : String
      getter playlist_name : String?
      getter song_position : Int32?
      getter song_uri : String?
      getter tooltip : String?
      getter children : Array(UInt64) = [] of UInt64

      def initialize(
        @id,
        @row_type,
        @title,
        @subtitle = "",
        @playlist_name = nil,
        @song_position = nil,
        @song_uri = nil,
        @tooltip = nil,
        @parent_id = nil,
        @row = 0,
      )
      end
    end

    @nodes = {} of UInt64 => Node
    @root_children = [] of UInt64
    @playlist_node_ids = {} of String => UInt64
    @next_id = 1_u64

    def replace(playlists : Array(PlaylistEntry)) : Nil
      begin_reset_model
      clear_nodes

      if playlists.empty?
        add_root(ROW_TYPE_MESSAGE, "No stored playlists")
      else
        playlists.each do |playlist|
          playlist_id = add_root(
            ROW_TYPE_PLAYLIST,
            playlist.name,
            playlist_subtitle(playlist),
            playlist.name,
            tooltip: playlist.tooltip
          )
          @playlist_node_ids[playlist.name] = playlist_id

          playlist.songs.each_with_index do |song, row|
            add_child(
              playlist_id,
              ROW_TYPE_SONG,
              song.title,
              song.subtitle,
              playlist.name,
              row,
              song.file || "",
              song.tooltip_html
            )
          end
        end
      end

      end_reset_model
    end

    def show_message(message : String) : Nil
      begin_reset_model
      clear_nodes
      add_root(ROW_TYPE_MESSAGE, message)
      end_reset_model
    end

    def playlist_names : Array(String)
      @playlist_node_ids.keys
    end

    def first_playlist_name : String?
      playlist_names.first?
    end

    def has_playlist?(name : String) : Bool
      @playlist_node_ids.has_key?(name)
    end

    def index_for_playlist(name : String) : Qt6::ModelIndex?
      id = @playlist_node_ids[name]?
      return unless id

      node = @nodes[id]?
      return unless node

      index(node.row, 0)
    end

    protected def model_row_count(parent : Qt6::ModelIndex) : Int32
      children_for(parent).size
    end

    protected def model_column_count(parent : Qt6::ModelIndex) : Int32
      1
    end

    protected def model_index_internal_id(row : Int32, column : Int32, parent : Qt6::ModelIndex) : UInt64?
      return unless column == 0

      children_for(parent)[row]?
    end

    protected def model_parent(index : Qt6::ModelIndex) : Qt6::ModelIndexSpec?
      node = node_for(index)
      return unless node

      parent_id = node.parent_id
      return unless parent_id

      parent = @nodes[parent_id]?
      return unless parent

      Qt6::ModelIndexSpec.new(parent.row, 0, parent.id)
    end

    protected def model_data(index : Qt6::ModelIndex, role : Int32) : Qt6::ModelData
      node = node_for(index)
      return nil unless node

      case role
      when Qt6::ItemDataRole::Display.value, ItemRoles::TITLE.value
        node.title
      when ItemRoles::SUBTITLE.value
        node.subtitle
      when ItemRoles::PLAYLIST_ROW_TYPE.value
        node.row_type
      when ItemRoles::PLAYLIST_NAME.value
        node.playlist_name
      when ItemRoles::PLAYLIST_SONG_POSITION.value
        node.song_position
      when ItemRoles::PLAYLIST_SONG_URI.value
        node.song_uri
      when Qt6::ItemDataRole::ToolTip.value
        node.tooltip
      else
        nil
      end
    end

    protected def model_header_data(section : Int32, orientation : Qt6::Orientation, role : Int32) : Qt6::ModelData
      return nil unless orientation.horizontal?
      return nil unless role == Qt6::ItemDataRole::Display.value

      section == 0 ? "Playlist" : nil
    end

    protected def model_flags(index : Qt6::ModelIndex) : Qt6::ItemFlag
      return Qt6::ItemFlag::None unless index.valid?

      node = node_for(index)
      return Qt6::ItemFlag::Enabled unless node

      case node.row_type
      when ROW_TYPE_PLAYLIST
        Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable | Qt6::ItemFlag::DropEnabled
      when ROW_TYPE_SONG
        Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable | Qt6::ItemFlag::DragEnabled
      else
        Qt6::ItemFlag::Enabled
      end
    end

    protected def model_mime_types : Array(String)
      [MIME_TYPE, "text/plain"]
    end

    protected def model_mime_data(indexes : Array(Qt6::ModelIndex)) : Qt6::MimeData?
      return unless indexes.any? { |index| song_index?(index) }

      mime = Qt6::MimeData.new
      mime.set_data(MIME_TYPE, "selection")
      mime.text = "garnetune-stored-playlist-selection"
      mime
    end

    protected def model_supported_drag_actions : Qt6::DropAction
      Qt6::DropAction::CopyAction | Qt6::DropAction::MoveAction
    end

    protected def model_supported_drop_actions : Qt6::DropAction
      Qt6::DropAction::MoveAction
    end

    private def clear_nodes : Nil
      @nodes.clear
      @root_children.clear
      @playlist_node_ids.clear
      @next_id = 1_u64
    end

    private def add_root(row_type : String, title : String, subtitle : String = "", playlist_name : String? = nil, song_position : Int32? = nil, song_uri : String? = nil, tooltip : String? = nil) : UInt64
      id = next_id
      row = @root_children.size
      node = Node.new(id, row_type, title, subtitle, playlist_name, song_position, song_uri, tooltip, nil, row)
      @nodes[id] = node
      @root_children << id
      id
    end

    private def add_child(parent_id : UInt64, row_type : String, title : String, subtitle : String = "", playlist_name : String? = nil, song_position : Int32? = nil, song_uri : String? = nil, tooltip : String? = nil) : UInt64
      parent = @nodes[parent_id]
      id = next_id
      row = parent.children.size
      node = Node.new(id, row_type, title, subtitle, playlist_name, song_position, song_uri, tooltip, parent_id, row)
      @nodes[id] = node
      parent.children << id
      id
    end

    private def next_id : UInt64
      id = @next_id
      @next_id += 1
      id
    end

    private def node_for(index : Qt6::ModelIndex) : Node?
      return unless index.valid?

      @nodes[index.internal_id]?
    end

    private def song_index?(index : Qt6::ModelIndex) : Bool
      return false unless index.valid? && index.column == 0

      node = node_for(index)
      !!node && node.row_type == ROW_TYPE_SONG
    end

    private def children_for(parent : Qt6::ModelIndex) : Array(UInt64)
      return @root_children unless parent.valid?

      @nodes[parent.internal_id]?.try(&.children) || [] of UInt64
    end

    private def playlist_subtitle(playlist : PlaylistEntry) : String
      playlist.summary || begin
        count = playlist.songs.size
        total = playlist.songs.compact_map(&.duration).sum
        "#{count} #{count == 1 ? "Track" : "Tracks"} (#{Song.format_time(total)})"
      end
    end
  end
end
