module MPDUI
  module AppSettingsDialog
    private def open_settings_dialog : Nil
      parent = @window
      return unless parent

      connect if SettingsDialog.edit(parent, @settings)
    end
  end
end
