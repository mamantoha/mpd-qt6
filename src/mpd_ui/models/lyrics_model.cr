module MPDUI
  class LyricsModel < Qt6::AbstractListModel
    @lines : Array(LyricsLine) = [] of LyricsLine
    @active_row : Int32? = nil
    @active_background : Qt6::Color?
    @active_foreground : Qt6::Color?

    def active_colors=(colors : Tuple(Qt6::Color, Qt6::Color)) : Tuple(Qt6::Color, Qt6::Color)
      @active_background = colors[0]
      @active_foreground = colors[1]
      colors
    end

    def replace(lines : Array(LyricsLine)) : Nil
      begin_reset_model
      @lines = lines
      @active_row = nil
      end_reset_model
    end

    def clear : Nil
      replace([] of LyricsLine)
    end

    def line_at(row : Int32) : LyricsLine?
      @lines[row]?
    end

    def active_row : Int32?
      @active_row
    end

    def active_row=(row : Int32?) : Nil
      row = nil unless row && row.in?(0...@lines.size)
      return if @active_row == row

      old_row = @active_row
      @active_row = row
      emit_row_changed(old_row)
      emit_row_changed(row)
    end

    protected def model_row_count : Int32
      @lines.size
    end

    protected def model_data(index : Qt6::ModelIndex, role : Int32) : Qt6::ModelData
      return unless index.valid?

      line = @lines[index.row]?
      return unless line

      case role
      when Qt6::ItemDataRole::Display.value
        line.text
      when ItemRoles::LYRICS_TIME_MS.value
        line.time.total_milliseconds.to_i
      when Qt6::ItemDataRole::TextAlignment.value
        (Qt6::AlignmentFlag::HCenter | Qt6::AlignmentFlag::VCenter).value
      when Qt6::ItemDataRole::Background.value
        @active_background if index.row == @active_row
      when Qt6::ItemDataRole::Foreground.value
        @active_foreground if index.row == @active_row
      end
    end

    protected def model_flags(index : Qt6::ModelIndex) : Qt6::ItemFlag
      return Qt6::ItemFlag::None unless index.valid?

      Qt6::ItemFlag::Enabled | Qt6::ItemFlag::Selectable
    end

    private def emit_row_changed(row : Int32?) : Nil
      return unless row && row.in?(0...@lines.size)

      changed_index = index(row, 0)
      begin
        data_changed(changed_index)
      ensure
        changed_index.release
      end
    end
  end
end
