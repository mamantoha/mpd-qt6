module MPDUI
  class SettingsDialog
    def self.edit(parent : Qt6::Widget, settings : Settings) : Bool
      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = "Connection Settings"
      dialog.resize(360, 150)

      host_edit = Qt6::LineEdit.new(settings.host, dialog)
      host_edit.placeholder_text = "localhost"

      port_spin = Qt6::SpinBox.new(dialog)
      port_spin.set_range(1, 65_535)
      port_spin.value = settings.port

      dialog.vbox do |column|
        host_row = Qt6::Widget.new(dialog)
        host_row.hbox do |row|
          row << Qt6::Label.new("Host")
          row << host_edit
        end

        port_row = Qt6::Widget.new(dialog)
        port_row.hbox do |row|
          row << Qt6::Label.new("Port")
          row << port_spin
        end

        button_row = Qt6::Widget.new(dialog)
        button_row.hbox do |row|
          cancel_button = Qt6::PushButton.new("Cancel")
          save_button = Qt6::PushButton.new("Save")

          cancel_button.on_clicked { dialog.reject }
          save_button.on_clicked do
            host = host_edit.text.strip

            if host.empty?
              Qt6::MessageBox.warning(dialog, title: "Invalid settings", text: "Host cannot be empty")
            else
              settings.host = host
              settings.port = port_spin.value
              settings.save
              dialog.accept
            end
          end

          row << cancel_button
          row << save_button
        end

        column << host_row
        column << port_row
        column << button_row
      end

      dialog.exec == Qt6::DialogCode::Accepted
    ensure
      dialog.try(&.release)
    end
  end
end
