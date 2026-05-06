module MPDUI
  class QueueController
    getter positions : Array(Int32) = [] of Int32
    getter ids : Array(Int32) = [] of Int32

    record MovePlan,
      current_ids : Array(Int32),
      desired_ids : Array(Int32),
      target_row : Int32

    def empty? : Bool
      @positions.empty?
    end

    def size : Int32
      @positions.size
    end

    def replace(songs : Array(Song)) : Nil
      @positions.clear
      @ids.clear

      songs.each_with_index do |song, row|
        pos = song.pos || row
        id = song.id || pos
        @positions << pos
        @ids << id
      end
    end

    def position_at(row : Int32) : Int32?
      @positions[row]?
    end

    def id_at(row : Int32) : Int32?
      @ids[row]?
    end

    def row_for_position(position : Int32) : Int32?
      @positions.index(position)
    end

    def positions_for_rows(rows : Array(Int32)) : Array(Int32)
      rows.compact_map { |row| position_at(row) }
    end

    def base_position_for_insert(row : Int32?) : Int32?
      return unless row
      return unless row < @positions.size

      @positions[row]? || row
    end

    def move_plan(insert_row : Int32, selected_rows : Array(Int32)) : MovePlan?
      rows = selected_rows.select { |row| row >= 0 && row < @ids.size }.sort!.uniq!
      return if rows.empty?

      selected_ids = rows.compact_map { |row| @ids[row]? }
      return if selected_ids.empty?

      current_ids = @ids.dup
      remaining_ids = current_ids.reject { |id| selected_ids.includes?(id) }
      target_row = insert_row.clamp(0, current_ids.size)
      target_row -= rows.count { |row| row < target_row }
      target_row = target_row.clamp(0, remaining_ids.size)

      desired_ids = remaining_ids.dup
      selected_ids.each_with_index do |id, offset|
        desired_ids.insert(target_row + offset, id)
      end
      return if desired_ids == current_ids

      MovePlan.new(current_ids, desired_ids, target_row)
    end
  end
end
