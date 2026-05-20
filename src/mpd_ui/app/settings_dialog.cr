module MPDUI
  class SettingsDialog
    def self.edit(parent : Qt6::Widget, settings : Settings) : Bool
      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = "Settings"
      dialog.resize(560, 320)

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

      save_settings = ->{
        host = host_edit.text.strip
        username = lastfm_username.text.strip
        password = lastfm_password.text

        if host.empty?
          Qt6::MessageBox.warning(dialog, title: "Invalid settings", text: "Host cannot be empty")
        elsif lastfm_enabled.checked? && username.empty?
          Qt6::MessageBox.warning(dialog, title: "Invalid Last.fm settings", text: "Last.fm username cannot be empty")
        elsif lastfm_enabled.checked? && settings.lastfm_session_key.empty? && password.empty?
          Qt6::MessageBox.warning(dialog, title: "Last.fm authentication required", text: "Enter your Last.fm password once to create a session")
        else
          authenticated = true
          if lastfm_enabled.checked? && !password.empty?
            begin
              lastfm_client = LastfmAdapter.client
              session = lastfm_client.mobile_session(username, password)
              settings.lastfm_username = session.username
              settings.lastfm_session_key = session.key
              lastfm_status.text = "Authenticated"
            rescue ex
              authenticated = false
              Qt6::MessageBox.warning(dialog, title: "Last.fm authentication failed", text: ex.message || ex.to_s)
            end
          else
            settings.lastfm_username = username
          end

          if authenticated
            settings.host = host
            settings.port = port_spin.value
            settings.lastfm_enabled = lastfm_enabled.checked?
            settings.save
            dialog.accept
          end
        end
      }

      tabs = Qt6::TabWidget.new(dialog)

      connection_page = Qt6::Widget.new(tabs)
      connection_page.vbox do |connection_column|
        connection_column.spacing = 10
        connection_column.set_contents_margins(10, 10, 10, 10)

        connection_group = Qt6::GroupBox.new("MPD Connection", connection_page)
        connection_group.vbox do |group_column|
          group_column.spacing = 8
          group_column.set_contents_margins(10, 10, 10, 10)

          host_row = Qt6::Widget.new(connection_group)
          host_row.hbox do |row|
            label = Qt6::Label.new("Host")
            label.fixed_width = 80
            row << label
            row << host_edit
          end

          port_row = Qt6::Widget.new(connection_group)
          port_row.hbox do |row|
            label = Qt6::Label.new("Port")
            label.fixed_width = 80
            row << label
            row << port_spin
            row.add_stretch
          end

          group_column << host_row
          group_column << port_row
        end

        connection_column << connection_group
        connection_column.add_stretch
      end

      lastfm_page = Qt6::Widget.new(tabs)
      lastfm_page.vbox do |lastfm_column|
        lastfm_column.spacing = 10
        lastfm_column.set_contents_margins(10, 10, 10, 10)

        lastfm_group = Qt6::GroupBox.new("Last.fm", lastfm_page)
        lastfm_group.vbox do |group_column|
          group_column.spacing = 8
          group_column.set_contents_margins(10, 10, 10, 10)

          username_row = Qt6::Widget.new(lastfm_group)
          username_row.hbox do |row|
            label = Qt6::Label.new("Username")
            label.fixed_width = 80
            row << label
            row << lastfm_username
          end

          password_row = Qt6::Widget.new(lastfm_group)
          password_row.hbox do |row|
            label = Qt6::Label.new("Password")
            label.fixed_width = 80
            row << label
            row << lastfm_password
          end

          group_column << lastfm_enabled
          group_column << username_row
          group_column << password_row
          group_column << lastfm_status
        end

        lastfm_column << lastfm_group
        lastfm_column.add_stretch
      end

      tabs.add_tab(connection_page, "MPD Connection")
      tabs.add_tab(lastfm_page, "Last.fm")

      button_box = Qt6::DialogButtonBox.new(
        Qt6::DialogButtonBoxStandardButton::Ok | Qt6::DialogButtonBoxStandardButton::Cancel,
        dialog
      )
      button_box.on_accepted { save_settings.call }
      button_box.on_rejected { dialog.reject }

      dialog.vbox do |column|
        column.spacing = 10
        column.set_contents_margins(10, 10, 10, 10)
        column << tabs
        column << button_box
      end

      dialog.exec == Qt6::DialogCode::Accepted
    ensure
      dialog.try(&.release)
    end
  end
end
