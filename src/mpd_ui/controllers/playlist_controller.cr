module MPDUI
  class PlaylistController
    record MovePlan,
      current_positions : Array(Int32),
      desired_positions : Array(Int32),
      moves : Array(Tuple(Int32, Int32)),
      target_position : Int32

    # Builds a safe sequence of MPD `playlistmove` calls for a multi-row move.
    #
    # Stored playlist rows only have positional indexes, not stable queue ids.
    # After each `playlistmove`, the remaining source positions can shift. To
    # avoid moving the wrong songs, this method simulates the reorder in memory:
    #
    # 1. Remove selected positions from the current order.
    # 2. Insert them at the drop target, preserving their selected order.
    # 3. Compare current order with desired order and emit the minimal sequence
    #    of `{current_index, desired_index}` moves while updating the simulated
    #    current order after each move.
    #
    # The returned moves are safe to pass to MPD in order:
    # `playlistmove name, from, to`.
    def move_plan(size : Int32, insert_position : Int32, selected_positions : Array(Int32)) : MovePlan?
      positions = selected_positions.select(&.in?(0...size)).sort!.uniq!
      return if positions.empty?

      current_positions = (0...size).to_a
      remaining_positions = current_positions.reject { |position| positions.includes?(position) }
      target_position = insert_position.clamp(0, current_positions.size)
      target_position -= positions.count { |position| position < target_position }
      target_position = target_position.clamp(0, remaining_positions.size)

      desired_positions = remaining_positions.dup
      positions.each_with_index do |position, offset|
        desired_positions.insert(target_position + offset, position)
      end
      return if desired_positions == current_positions

      moves = [] of Tuple(Int32, Int32)
      simulated_positions = current_positions.dup
      desired_positions.each_with_index do |position, desired_index|
        current_index = simulated_positions.index(position)
        next unless current_index
        next if current_index == desired_index

        moves << {current_index, desired_index}
        moved_position = simulated_positions.delete_at(current_index)
        simulated_positions.insert(desired_index, moved_position)
      end

      MovePlan.new(current_positions, desired_positions, moves, target_position)
    end
  end
end
