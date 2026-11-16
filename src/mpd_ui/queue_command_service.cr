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

    def delete_ids(client : MPD::Client, ids : Array(Int32)) : Nil
      client.with_command_list do
        ids.each { |id| client.deleteid(id) }
      end
    end
  end
end
