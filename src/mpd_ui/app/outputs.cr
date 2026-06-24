module MPDUI
  module AppOutputs
    private record MpdOutput,
      id : String,
      name : String,
      enabled : Bool,
      plugin : String?

    private def refresh_outputs_menu : Nil
      menu = @app_actions.try(&.outputs_menu)
      return unless menu

      @output_actions.clear
      menu.clear

      outputs = mpd_outputs
      if outputs.empty?
        action = menu.add_action("No outputs")
        action.enabled = false
        @output_actions << action
        return
      end

      outputs.each do |output|
        action = Qt6::Action.new(output.name, menu)
        action.checkable = true
        action.checked = output.enabled
        action.tool_tip = output.plugin ? "ID #{output.id} • #{output.plugin}" : "ID #{output.id}"
        action.on_toggled do |enabled|
          set_mpd_output_enabled(output, enabled)
          refresh_outputs_menu
          state = enabled ? "Enabled" : "Disabled"
          message = "#{state} output #{output.name}"
          set_status(message)
          show_tray_message(message)
        rescue ex
          refresh_outputs_menu
          Qt6::MessageBox.warning(@window, title: "Output Change Failed", text: ex.message || ex.to_s) if @window
        end
        menu.add_action(action)
        @output_actions << action
      end
    rescue ex
      action = menu.try(&.add_action("Unable to load outputs"))
      if action
        action.enabled = false
        action.tool_tip = ex.message || ex.to_s
        @output_actions << action
      end
    end

    private def clear_outputs_menu(message : String) : Nil
      menu = @app_actions.try(&.outputs_menu)
      return unless menu

      @output_actions.clear
      menu.clear

      action = menu.add_action(message)
      action.enabled = false
      @output_actions << action
    end

    private def mpd_outputs : Array(MpdOutput)
      client = @client
      return [] of MpdOutput unless client

      raw_outputs = client.outputs
      objects = [] of MPD::Object
      case raw_outputs
      when Array
        raw_outputs.each { |object| objects << object }
      when Hash
        objects << raw_outputs
      end

      objects.compact_map do |metadata|
        id = metadata["outputid"]?
        next unless id

        name = metadata["outputname"]?
        enabled = metadata["outputenabled"]? == "1"
        MpdOutput.new(
          id: id,
          name: name && !name.empty? ? name : "Output #{id}",
          enabled: enabled,
          plugin: metadata["plugin"]?
        )
      end
    end

    private def set_mpd_output_enabled(output : MpdOutput, enabled : Bool) : Nil
      client = @client
      raise "Not connected to MPD" unless client

      if enabled
        client.enableoutput(output.id)
      else
        client.disableoutput(output.id)
      end
    end
  end
end
