module MPDUI
  class SettingsDialog
    def self.edit(parent : Qt6::Widget, settings : Settings) : Bool
      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = tr("Settings")
      dialog.resize(680, 340)

      host_edit = Qt6::LineEdit.new(settings.host, dialog)
      host_edit.placeholder_text = tr("localhost")

      port_spin = Qt6::SpinBox.new(dialog)
      port_spin.set_range(1, 65_535)
      port_spin.value = settings.port

      lastfm_enabled = Qt6::CheckBox.new(tr("Scrobble songs to Last.fm"), dialog)
      lastfm_enabled.checked = settings.lastfm_enabled?

      lastfm_username = Qt6::LineEdit.new(settings.lastfm_username, dialog)
      lastfm_username.placeholder_text = tr("Last.fm username")

      lastfm_password = Qt6::LineEdit.new("", dialog)
      lastfm_password.placeholder_text = settings.lastfm_session_key.empty? ? tr("Last.fm password") : tr("Leave empty to keep existing session")
      lastfm_password.echo_mode = Qt6::EchoMode::Password

      lastfm_status = Qt6::Label.new(settings.lastfm_session_key.empty? ? tr("Not authenticated") : tr("Authenticated"))
      lastfm_status.word_wrap = true
      authenticate_lastfm_button = Qt6::PushButton.new(tr("Authenticate"), dialog)

      pending_lastfm_username = settings.lastfm_username
      pending_lastfm_session_key = settings.lastfm_session_key
      tabs = Qt6::TabWidget.new(dialog)

      authenticate_lastfm = -> {
        username = lastfm_username.text.strip
        password = lastfm_password.text

        if username.empty?
          tabs.current_index = 1
          lastfm_status.text = tr("Last.fm username cannot be empty")
          false
        elsif password.empty?
          tabs.current_index = 1
          lastfm_status.text = tr("Enter your Last.fm password to authenticate")
          false
        else
          authenticate_lastfm_button.enabled = false
          lastfm_status.text = tr("Authenticating...")
          begin
            session = LastfmAdapter.client.mobile_session(username, password)
            pending_lastfm_username = session.username
            pending_lastfm_session_key = session.key
            lastfm_username.text = session.username
            lastfm_password.clear
            lastfm_password.placeholder_text = tr("Leave empty to keep existing session")
            lastfm_status.text = tr("Authenticated as %1").sub("%1", session.username)
            true
          rescue ex
            tabs.current_index = 1
            lastfm_status.text = tr("Authentication failed: %1").sub("%1", (ex.message || ex).to_s)
            false
          ensure
            authenticate_lastfm_button.enabled = true
          end
        end
      }

      save_settings = -> {
        host = host_edit.text.strip
        username = lastfm_username.text.strip
        password = lastfm_password.text

        if host.empty?
          Qt6::MessageBox.warning(dialog, title: tr("Invalid settings"), text: tr("Host cannot be empty"))
        elsif lastfm_enabled.checked? && username.empty?
          tabs.current_index = 1
          lastfm_status.text = tr("Last.fm username cannot be empty")
        elsif lastfm_enabled.checked? && password.empty? && username != pending_lastfm_username
          tabs.current_index = 1
          lastfm_status.text = tr("Enter your Last.fm password to authenticate this username")
        elsif lastfm_enabled.checked? && pending_lastfm_session_key.empty? && password.empty?
          tabs.current_index = 1
          lastfm_status.text = tr("Enter your Last.fm password once to create a session")
        else
          authenticated = true
          if lastfm_enabled.checked? && !password.empty?
            authenticated = authenticate_lastfm.call
          end

          if authenticated
            settings.host = host
            settings.port = port_spin.value
            settings.lastfm_enabled = lastfm_enabled.checked?
            settings.lastfm_username = lastfm_enabled.checked? ? pending_lastfm_username : username
            settings.lastfm_session_key = pending_lastfm_session_key
            settings.save
            dialog.accept
          end
        end
      }

      connection_page = Qt6::Widget.new(tabs)
      connection_page.vbox do |connection_column|
        connection_column.spacing = 10
        connection_column.set_contents_margins(10, 10, 10, 10)

        connection_group = Qt6::GroupBox.new(tr("MPD Connection"), connection_page)
        connection_group.vbox do |group_column|
          group_column.spacing = 8
          group_column.set_contents_margins(10, 10, 10, 10)

          form = Qt6::FormLayout.new
          form.field_growth_policy = Qt6::FormLayoutFieldGrowthPolicy::AllNonFixedFieldsGrow
          form.row_wrap_policy = Qt6::FormLayoutRowWrapPolicy::WrapLongRows
          form.horizontal_spacing = 12
          form.vertical_spacing = 8
          form.add_row(tr("Host"), host_edit)
          form.add_row(tr("Port"), port_spin)
          group_column.add(form)
        end

        connection_column << connection_group
        connection_column.add_stretch
      end

      lastfm_page = Qt6::Widget.new(tabs)
      lastfm_page.vbox do |lastfm_column|
        lastfm_column.spacing = 10
        lastfm_column.set_contents_margins(10, 10, 10, 10)

        lastfm_group = Qt6::GroupBox.new(tr("Last.fm"), lastfm_page)
        lastfm_group.vbox do |group_column|
          group_column.spacing = 8
          group_column.set_contents_margins(10, 10, 10, 10)

          password_field = Qt6::Widget.new(lastfm_group)
          password_field.hbox do |row|
            row << lastfm_password
            row << authenticate_lastfm_button
          end

          form = Qt6::FormLayout.new
          form.field_growth_policy = Qt6::FormLayoutFieldGrowthPolicy::AllNonFixedFieldsGrow
          form.row_wrap_policy = Qt6::FormLayoutRowWrapPolicy::WrapLongRows
          form.horizontal_spacing = 12
          form.vertical_spacing = 8
          form.add_row(lastfm_enabled)
          form.add_row(tr("Username"), lastfm_username)
          form.add_row(tr("Password"), password_field)
          form.add_row(lastfm_status)
          group_column.add(form)
        end

        lastfm_column << lastfm_group
        lastfm_column.add_stretch
      end

      tabs.add_tab(connection_page, tr("MPD Connection"))
      tabs.add_tab(lastfm_page, tr("Last.fm"))

      button_box = Qt6::DialogButtonBox.new(
        Qt6::DialogButtonBoxStandardButton::Ok | Qt6::DialogButtonBoxStandardButton::Cancel,
        dialog
      )
      button_box.on_accepted { save_settings.call }
      button_box.on_rejected { dialog.reject }
      authenticate_lastfm_button.on_clicked { authenticate_lastfm.call }

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

    private def self.tr(text : String) : String
      I18n.t("SettingsDialog", text)
    end
  end
end
