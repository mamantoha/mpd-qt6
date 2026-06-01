module MPDUI
  class QueueModel < Qt6::AbstractTreeModel
    MIME_TYPE          = "application/x-garnetune-queue-row"
    QT_ITEM_MODEL_MIME = "application/x-qabstractitemmodeldatalist"

    @songs : Array(Song) = [] of Song
    @indicators : Array(String) = [] of String

    def replace(songs : Array(Song), &indicator_for : Int32 -> String) : Nil
      new_indicators = indicators_for(songs) { |pos| indicator_for.call(pos) }
      return replace_incrementally(songs, new_indicators) if can_diff_by_id?(@songs, songs)

      begin_reset_model
      @songs = songs
      @indicators = new_indicators
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
      return unless index.valid?

      song = @songs[index.row]?
      return unless song

      case role
      when Qt6::ItemDataRole::Display.value
        display_data(song, index)
      when Qt6::ItemDataRole::ToolTip.value
        song.tooltip_html
      when Qt6::ItemDataRole::TextAlignment.value
        if index.column == 2
          (Qt6::AlignmentFlag::Right | Qt6::AlignmentFlag::VCenter).value
        end
      end
    end

    protected def model_header_data(section : Int32, orientation : Qt6::Orientation, role : Int32) : Qt6::ModelData
      return unless orientation.horizontal?
      return unless role == Qt6::ItemDataRole::Display.value

      case section
      when 0 then "State"
      when 1 then "Track"
      when 2 then "Time"
      end
    end

    protected def model_flags(index : Qt6::ModelIndex) : Qt6::ItemFlag
      return Qt6::ItemFlag::Enabled | Qt6::ItemFlag::DropEnabled unless index.valid?

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

    private def indicators_for(songs : Array(Song), &indicator_for : Int32 -> String) : Array(String)
      songs.map_with_index do |song, row|
        indicator_for.call(song.pos || row)
      end
    end

    private def can_diff_by_id?(old_songs : Array(Song), new_songs : Array(Song)) : Bool
      old_songs.all?(&.id) && new_songs.all?(&.id)
    end

    private def replace_incrementally(new_songs : Array(Song), new_indicators : Array(String)) : Nil
      old_ids = @songs.compact_map(&.id)
      new_ids = new_songs.compact_map(&.id)

      if old_ids == new_ids
        @songs = new_songs
        @indicators = new_indicators
        emit_all_rows_changed unless @songs.empty?
        return
      end

      first_changed = first_changed_row(old_ids, new_ids)
      old_suffix, new_suffix = matching_suffix_lengths(old_ids, new_ids, first_changed)
      removed_count = old_ids.size - first_changed - old_suffix
      inserted_count = new_ids.size - first_changed - new_suffix

      if removed_count > 0 && inserted_count == 0
        begin_remove_rows(first_changed, first_changed + removed_count - 1)
        @songs = new_songs
        @indicators = new_indicators
        end_remove_rows
      elsif inserted_count > 0 && removed_count == 0
        begin_insert_rows(first_changed, first_changed + inserted_count - 1)
        @songs = new_songs
        @indicators = new_indicators
        end_insert_rows
      else
        begin_reset_model
        @songs = new_songs
        @indicators = new_indicators
        end_reset_model
      end
    end

    private def first_changed_row(old_ids : Array(Int32), new_ids : Array(Int32)) : Int32
      limit = Math.min(old_ids.size, new_ids.size)
      limit.times do |row|
        return row unless old_ids[row] == new_ids[row]
      end
      limit
    end

    private def matching_suffix_lengths(old_ids : Array(Int32), new_ids : Array(Int32), first_changed : Int32) : Tuple(Int32, Int32)
      old_index = old_ids.size - 1
      new_index = new_ids.size - 1
      old_count = 0
      new_count = 0

      while old_index >= first_changed && new_index >= first_changed && old_ids[old_index] == new_ids[new_index]
        old_count += 1
        new_count += 1
        old_index -= 1
        new_index -= 1
      end

      {old_count, new_count}
    end

    private def emit_all_rows_changed : Nil
      top_left = index(0, 0)
      bottom_right = index(@songs.size - 1, 2)
      begin
        data_changed(top_left, bottom_right)
      ensure
        top_left.release
        bottom_right.release
      end
    end
  end
end
