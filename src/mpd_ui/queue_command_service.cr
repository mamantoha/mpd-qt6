module MPDUI
  class QueueCommandService
    def move_to_plan(client : MPD::Client, plan : QueueController::MovePlan) : Nil
      current_ids = plan.current_ids

      client.with_command_list do
        plan.desired_ids.each_with_index do |id, desired_index|
          current_index = current_ids.index(id)
          next unless current_index
          next if current_index == desired_index

          client.moveid(id, desired_index)
          moved_id = current_ids.delete_at(current_index)
          current_ids.insert(desired_index, moved_id)
        end
      end
    end

    def delete_position_ranges(client : MPD::Client, ranges : Array(Tuple(Int32, Int32)), queue_size : Int32) : Nil
      selected_count = ranges.sum { |first, last| last - first + 1 }
      if selected_count >= queue_size
        client.clear
        return
      end

      client.with_command_list do
        ranges.sort_by { |first, _last| first }.reverse_each do |first, last|
          if first == last
            client.delete(first)
          else
            client.delete(first..last)
          end
        end
      end
    end
  end
end
