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

      client = @client
      unless client
        clear_outputs_menu("Disconnected")
        return
      end

      clear_outputs_menu("Loading outputs…")
      run_background(
        ->(outputs : Array(MpdOutput)) {
          render_outputs_menu(outputs) if @client == client
        },
        ->(ex : Exception) {
          if @client == client
            clear_outputs_menu("Unable to load outputs")
            @output_actions.each(&.tool_tip=(ex.message || ex.to_s))
          end
        }
      ) do
        mpd_outputs(client)
      end
    end

    private def render_outputs_menu(outputs : Array(MpdOutput)) : Nil
      menu = @app_actions.try(&.outputs_menu)
      return unless menu

      @output_actions.clear
      menu.clear

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
          action.enabled = false
          set_mpd_output_enabled(output, enabled)
        end
        menu.add_action(action)
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

    private def mpd_outputs(client : MPD::Client) : Array(MpdOutput)
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
      unless client
        clear_outputs_menu("Disconnected")
        return
      end

      run_background(
        ->(_result : Nil) {
          if @client == client
            refresh_outputs_menu
            state = enabled ? "Enabled" : "Disabled"
            message = "#{state} output #{output.name}"
            set_status(message)
            show_tray_message(message)
          end
        },
        ->(ex : Exception) {
          if @client == client
            refresh_outputs_menu
            Qt6::MessageBox.warning(@window, title: "Output Change Failed", text: ex.message || ex.to_s) if @window
          end
        }
      ) do
        if enabled
          client.enableoutput(output.id)
        else
          client.disableoutput(output.id)
        end
        nil
      end
    end
  end
end
