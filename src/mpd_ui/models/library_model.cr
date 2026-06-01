module MPDUI
  class LibraryModel < Qt6::AbstractTreeModel
    MIME_TYPE = "application/x-garnetune-library-uri-list"

    private enum NodeKind
      Message
      Artist
      Album
      Song
    end

    private class Node
      getter id : UInt64
      property parent_id : UInt64?
      property row : Int32
      getter kind : NodeKind
      getter title : String
      getter subtitle : String
      getter file : String?
      getter tooltip : String?
      getter children : Array(UInt64) = [] of UInt64

      def initialize(@id, @kind, @title, @subtitle = "", @file = nil, @tooltip = nil, @parent_id = nil, @row = 0)
      end
    end

    @nodes = {} of UInt64 => Node
    @root_children = [] of UInt64
    @next_id = 1_u64

    def replace(result : LibraryIndex::Result) : Nil
      begin_reset_model
      clear_nodes

      if result.artists.empty?
        add_root(NodeKind::Message, result.filtered ? "No matching songs" : "Database is empty")
      else
        result.artists.each do |artist|
          artist_id = add_root(NodeKind::Artist, artist.name, artist.summary)

          artist.albums.each do |album|
            album_id = add_child(artist_id, NodeKind::Album, album.title, album.summary)

            album.songs.each do |song|
              add_child(
                album_id,
                NodeKind::Song,
                song_title(song),
                song.duration_label,
                song.file,
                song.tooltip_html
              )
            end
          end
        end
      end
      end_reset_model
    end

    def show_message(message : String) : Nil
      begin_reset_model
      clear_nodes
      add_root(NodeKind::Message, message)
      end_reset_model
    end

    def uris_for_indexes(indexes : Enumerable(Qt6::ModelIndex), selection_model : Qt6::ItemSelectionModel? = nil) : Array(String)
      uris = [] of String
      indexes.each do |index|
        next unless index.valid?
        next unless index.column == 0
        next if selection_model && selected_ancestor?(selection_model, index)

        collect_uris(index.internal_id, uris)
      end
      uris.uniq!
    end

    def uris_for_index(index : Qt6::ModelIndex) : Array(String)
      uris = [] of String
      collect_uris(index.internal_id, uris) if index.valid?
      uris.uniq!
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
      when Qt6::ItemDataRole::User.value
        node.file
      when Qt6::ItemDataRole::ToolTip.value
        node.tooltip
      else
        nil
      end
    end

    protected def model_header_data(section : Int32, orientation : Qt6::Orientation, role : Int32) : Qt6::ModelData
      return nil unless orientation.horizontal?
      return nil unless role == Qt6::ItemDataRole::Display.value

      section == 0 ? "Database" : nil
    end

    protected def model_flags(index : Qt6::ModelIndex) : Qt6::ItemFlag
      return Qt6::ItemFlag::None unless index.valid?

      flags = Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable
      node = node_for(index)
      if node && node.kind != NodeKind::Message
        flags |= Qt6::ItemFlag::DragEnabled
      end
      flags
    end

    protected def model_mime_types : Array(String)
      [MIME_TYPE, "text/plain"]
    end

    protected def model_mime_data(indexes : Array(Qt6::ModelIndex)) : Qt6::MimeData?
      return unless indexes.any? { |index| draggable_index?(index) }

      mime = Qt6::MimeData.new
      mime.set_data(MIME_TYPE, "selection")
      mime.text = "garnetune-library-selection"
      mime
    end

    protected def model_supported_drag_actions : Qt6::DropAction
      Qt6::DropAction::CopyAction
    end

    private def clear_nodes : Nil
      @nodes.clear
      @root_children.clear
      @next_id = 1_u64
    end

    private def add_root(kind : NodeKind, title : String, subtitle : String = "", file : String? = nil, tooltip : String? = nil) : UInt64
      id = next_id
      row = @root_children.size
      node = Node.new(id, kind, title, subtitle, file, tooltip, nil, row)
      @nodes[id] = node
      @root_children << id
      id
    end

    private def add_child(parent_id : UInt64, kind : NodeKind, title : String, subtitle : String = "", file : String? = nil, tooltip : String? = nil) : UInt64
      parent = @nodes[parent_id]
      id = next_id
      row = parent.children.size
      node = Node.new(id, kind, title, subtitle, file, tooltip, parent_id, row)
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

    private def draggable_index?(index : Qt6::ModelIndex) : Bool
      return false unless index.valid?

      node = node_for(index)
      !!node && node.kind != NodeKind::Message
    end

    private def children_for(parent : Qt6::ModelIndex) : Array(UInt64)
      return @root_children unless parent.valid?

      @nodes[parent.internal_id]?.try(&.children) || [] of UInt64
    end

    private def collect_uris(node_id : UInt64, uris : Array(String)) : Nil
      node = @nodes[node_id]?
      return unless node

      if file = node.file
        uris << file unless file.empty?
      end

      node.children.each do |child_id|
        collect_uris(child_id, uris)
      end
    end

    private def selected_ancestor?(selection_model : Qt6::ItemSelectionModel, index : Qt6::ModelIndex) : Bool
      parent = index.parent(self)

      loop do
        begin
          return false unless parent.valid?
          return true if selection_model.selected?(parent)

          next_parent = parent.parent(self)
        ensure
          parent.release
        end

        parent = next_parent
      end
    end

    private def song_title(song : Song) : String
      song.database_label.split(" • ", 2).first
    end
  end
end
