module MPDUI
  class QueueModel < Qt6::AbstractTreeModel
    MIME_TYPE          = "application/x-garnetune-queue-row"
    QT_ITEM_MODEL_MIME = "application/x-qabstractitemmodeldatalist"

    @songs : Array(Song) = [] of Song
    @indicators : Array(String) = [] of String

    def replace(songs : Array(Song), &indicator_for : Int32 -> String) : Nil
      begin_reset_model
      @songs = songs
      @indicators = songs.map_with_index do |song, row|
        indicator_for.call(song.pos || row)
      end
      end_reset_model
    end

    def update_indicator(row : Int32, value : String) : Nil
      return if row < 0 || row >= @indicators.size
      return if @indicators[row] == value

      @indicators[row] = value
      index = self.index(row, 0)
      begin
        data_changed(index)
      ensure
        index.release
      end
    end

    def song_at(row : Int32) : Song?
      @songs[row]?
    end

    protected def model_row_count(parent : Qt6::ModelIndex) : Int32
      parent.valid? ? 0 : @songs.size
    end

    protected def model_column_count(parent : Qt6::ModelIndex) : Int32
      parent.valid? ? 0 : 3
    end

    protected def model_index_internal_id(row : Int32, column : Int32, parent : Qt6::ModelIndex) : UInt64?
      return if parent.valid?
      return unless row.in?(0...@songs.size)
      return unless column.in?(0..2)

      (row + 1).to_u64
    end

    protected def model_parent(index : Qt6::ModelIndex) : Qt6::ModelIndexSpec?
      nil
    end

    protected def model_data(index : Qt6::ModelIndex, role : Int32) : Qt6::ModelData
      return nil unless index.valid?

      song = @songs[index.row]?
      return nil unless song

      case role
      when Qt6::ItemDataRole::Display.value
        display_data(song, index)
      when Qt6::ItemDataRole::ToolTip.value
        song.tooltip_html
      when Qt6::ItemDataRole::TextAlignment.value
        if index.column == 2
          (Qt6::AlignmentFlag::Right | Qt6::AlignmentFlag::VCenter).value
        end
      else
        nil
      end
    end

    protected def model_header_data(section : Int32, orientation : Qt6::Orientation, role : Int32) : Qt6::ModelData
      return nil unless orientation.horizontal?
      return nil unless role == Qt6::ItemDataRole::Display.value

      case section
      when 0 then "State"
      when 1 then "Track"
      when 2 then "Time"
      end
    end

    protected def model_flags(index : Qt6::ModelIndex) : Qt6::ItemFlag
      return Qt6::ItemFlag::DropEnabled unless index.valid?

      Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable | Qt6::ItemFlag::DragEnabled | Qt6::ItemFlag::DropEnabled
    end

    protected def model_mime_types : Array(String)
      [MIME_TYPE, QT_ITEM_MODEL_MIME, "text/plain"]
    end

    protected def model_mime_data(indexes : Array(Qt6::ModelIndex)) : Qt6::MimeData?
      rows = indexes.compact_map do |index|
        next unless index.valid?
        index.row
      end.uniq!.sort!
      return if rows.empty?

      mime = Qt6::MimeData.new
      value = rows.join(",")
      mime.set_data(MIME_TYPE, value)
      mime.text = value
      mime
    end

    protected def model_drop_mime_data(mime_data : Qt6::MimeData, action : Qt6::DropAction, row : Int32, column : Int32, parent : Qt6::ModelIndex) : Bool
      return false if action == Qt6::DropAction::IgnoreAction

      mime_data.has_format?(MIME_TYPE) || mime_data.has_format?(QT_ITEM_MODEL_MIME) || mime_data.has_text?
    end

    protected def model_supported_drag_actions : Qt6::DropAction
      Qt6::DropAction::MoveAction
    end

    protected def model_supported_drop_actions : Qt6::DropAction
      Qt6::DropAction::CopyAction | Qt6::DropAction::MoveAction
    end

    private def display_data(song : Song, index : Qt6::ModelIndex) : String
      case index.column
      when 0
        @indicators[index.row]? || ""
      when 1
        song.queue_title
      when 2
        song.duration_label
      else
        ""
      end
    end
  end
end
