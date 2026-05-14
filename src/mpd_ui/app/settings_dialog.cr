module MPDUI
  class SettingsDialog
    def self.edit(parent : Qt6::Widget, settings : Settings) : Bool
      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = "Settings"
      dialog.resize(460, 300)

      host_edit = Qt6::LineEdit.new(settings.host, dialog)
      host_edit.placeholder_text = "localhost"

      port_spin = Qt6::SpinBox.new(dialog)
      port_spin.set_range(1, 65_535)
      port_spin.value = settings.port

      lastfm_enabled = Qt6::CheckBox.new("Scrobble songs to Last.fm", dialog)
      lastfm_enabled.checked = settings.lastfm_enabled?

      lastfm_username = Qt6::LineEdit.new(settings.lastfm_username, dialog)
      lastfm_username.placeholder_text = "Last.fm username"

      lastfm_password = Qt6::LineEdit.new("", dialog)
      lastfm_password.placeholder_text = settings.lastfm_session_key.empty? ? "Last.fm password" : "Leave empty to keep existing session"
      lastfm_password.echo_mode = Qt6::EchoMode::Password

      lastfm_status = Qt6::Label.new(settings.lastfm_session_key.empty? ? "Not authenticated" : "Authenticated")

      dialog.vbox do |column|
        column.spacing = 10

        connection_group = Qt6::GroupBox.new("MPD Connection", dialog)
        connection_group.vbox do |connection_column|
          connection_column.spacing = 6
          connection_column.set_contents_margins(8, 8, 8, 8)

          host_row = Qt6::Widget.new(connection_group)
          host_row.hbox do |row|
            row << Qt6::Label.new("Host")
            row << host_edit
          end

          port_row = Qt6::Widget.new(connection_group)
          port_row.hbox do |row|
            row << Qt6::Label.new("Port")
            row << port_spin
          end

          connection_column << host_row
          connection_column << port_row
        end

        lastfm_group = Qt6::GroupBox.new("Last.fm", dialog)
        lastfm_group.vbox do |lastfm_column|
          lastfm_column.spacing = 6
          lastfm_column.set_contents_margins(8, 8, 8, 8)

          username_row = Qt6::Widget.new(lastfm_group)
          username_row.hbox do |row|
            row << Qt6::Label.new("Username")
            row << lastfm_username
          end

          password_row = Qt6::Widget.new(lastfm_group)
          password_row.hbox do |row|
            row << Qt6::Label.new("Password")
            row << lastfm_password
          end

          lastfm_column << lastfm_enabled
          lastfm_column << username_row
          lastfm_column << password_row
          lastfm_column << lastfm_status
        end

        button_row = Qt6::Widget.new(dialog)
        button_row.hbox do |row|
          cancel_button = Qt6::PushButton.new("Cancel")
          save_button = Qt6::PushButton.new("Save")

          cancel_button.on_clicked { dialog.reject }
          save_button.on_clicked do
            host = host_edit.text.strip
            username = lastfm_username.text.strip
            password = lastfm_password.text

            if host.empty?
              Qt6::MessageBox.warning(dialog, title: "Invalid settings", text: "Host cannot be empty")
              next
            end

            if lastfm_enabled.checked? && username.empty?
              Qt6::MessageBox.warning(dialog, title: "Invalid Last.fm settings", text: "Last.fm username cannot be empty")
              next
            end

            if lastfm_enabled.checked? && settings.lastfm_session_key.empty? && password.empty?
              Qt6::MessageBox.warning(dialog, title: "Last.fm authentication required", text: "Enter your Last.fm password once to create a session")
              next
            end

            if lastfm_enabled.checked? && !password.empty?
              begin
                lastfm_client = LastfmAdapter.client
                session = lastfm_client.mobile_session(username, password)
                settings.lastfm_username = session.username
                settings.lastfm_session_key = session.key
                lastfm_status.text = "Authenticated"
              rescue ex
                Qt6::MessageBox.warning(dialog, title: "Last.fm authentication failed", text: ex.message || ex.to_s)
                next
              end
            else
              settings.lastfm_username = username
            end

            settings.host = host
            settings.port = port_spin.value
            settings.lastfm_enabled = lastfm_enabled.checked?
            settings.save
            dialog.accept
          end

          row.add_stretch
          row << cancel_button
          row << save_button
        end

        column << connection_group
        column << lastfm_group
        column << button_row
      end

      dialog.exec == Qt6::DialogCode::Accepted
    ensure
      dialog.try(&.release)
    end
  end
end
