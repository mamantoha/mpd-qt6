module MPDUI
  class QueueSelection
    def initialize(@view : Qt6::TreeView)
    end

    def selected_rows : Array(Int32)
      selected_row_ranges.flat_map do |first, last|
        (first..last).to_a
      end
    end

    def selected_row_ranges : Array(Tuple(Int32, Int32))
      selection_model = @view.selection_model
      return current_row_ranges unless selection_model

      ranges = [] of Tuple(Int32, Int32)
      selection = selection_model.selection
      begin
        selection.count.times do |index|
          range = selection.at(index)
          begin
            next if range.bottom < range.top
            next unless range.left <= 0 && range.right >= 0

            ranges << {range.top, range.bottom}
          ensure
            range.release
          end
        end
      ensure
        selection.release
      end

      ranges.empty? ? current_row_ranges : merge_row_ranges(ranges)
    end

    def selected_row_count : Int32
      selected_row_ranges.sum do |first, last|
        last - first + 1
      end
    end

    def selected_row?(row : Int32) : Bool
      selected_row_ranges.any? do |first, last|
        row.in?(first..last)
      end
    end

    def current_rows : Array(Int32)
      index = @view.current_index
      begin
        index.valid? ? [index.row] : [] of Int32
      ensure
        index.release
      end
    end

    private def current_row_ranges : Array(Tuple(Int32, Int32))
      current_rows.map { |row| {row, row} }
    end

    private def merge_row_ranges(ranges : Array(Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32))
      sorted = ranges.sort_by { |first, _last| first }
      merged = [] of Tuple(Int32, Int32)

      sorted.each do |first, last|
        if current = merged.last?
          current_first, current_last = current
          if first <= current_last + 1
            merged[-1] = {current_first, Math.max(current_last, last)}
            next
          end
        end

        merged << {first, last}
      end

      merged
    end
  end
end
