module MPDUI
  class ApplicationMenu
    getter about_action : Qt6::Action
    getter settings_action : Qt6::Action
    getter outputs_action : Qt6::Action
    getter search_library_action : Qt6::Action
    getter reload_database_action : Qt6::Action
    getter expanded_interface_action : Qt6::Action
    getter show_library_action : Qt6::Action
    getter show_main_menu_action : Qt6::Action
    getter blurred_cover_background_action : Qt6::Action

    getter outputs_menu : Qt6::Menu

    def initialize(
      window : Qt6::MainWindow,
      settings : Settings,
      on_about : ->,
      on_expanded_interface_changed : Bool ->,
      on_blurred_cover_background_changed : Bool ->,
      on_settings : ->,
      on_outputs : ->,
      on_quit : ->,
      on_show_library_changed : Bool ->,
      on_search_library : ->,
      on_reload_database : ->,
      on_save_queue_as_playlist : ->,
      on_clear_queue : ->,
    )
      menu_bar = window.menu_bar

      # App menu

      app_menu = Qt6::Menu.new("&App")

      @about_action = Qt6::Action.new("About", window).tap do |action|
        icon = Qt6::QIcon.from_theme("help-about")
        action.icon = icon unless icon.null?
        action.on_triggered { on_about.call }
      end

      @expanded_interface_action = Qt6::Action.new("Expanded Interface", window).tap do |action|
        icon = Qt6::QIcon.from_theme("view-fullscreen")
        action.icon = icon unless icon.null?
        action.checkable = true
        action.checked = settings.expanded_interface?
        action.on_toggled { |checked| on_expanded_interface_changed.call(checked) }
      end

      @blurred_cover_background_action = Qt6::Action.new("Blurred Cover Background", window).tap do |action|
        icon = Qt6::QIcon.from_theme("image-x-generic")
        action.icon = icon unless icon.null?
        action.checkable = true
        action.checked = settings.blurred_cover_background?
        action.on_toggled { |checked| on_blurred_cover_background_changed.call(checked) }
      end

      @show_main_menu_action = Qt6::Action.new("Show Main Menu", window).tap do |action|
        icon = Qt6::QIcon.from_theme("show-menu")
        action.icon = icon unless icon.null?
        action.checkable = true
        action.checked = settings.show_main_menu?
        action.shortcut = "Ctrl+M"
        action.on_toggled do |checked|
          window.menu_bar.visible = checked
          if settings.show_main_menu? != checked
            settings.show_main_menu = checked
            settings.save
          end
        end
      end

      @settings_action = Qt6::Action.new("Settings", window).tap do |action|
        icon = Qt6::QIcon.from_theme("preferences-system")
        action.icon = icon unless icon.null?
        action.shortcut = "Ctrl+,"
        action.on_triggered { on_settings.call }
      end

      @outputs_menu = Qt6::Menu.new("Outputs", app_menu)
      @outputs_action = @outputs_menu.menu_action.tap do |action|
        icon = Qt6::QIcon.from_theme("audio-speakers")
        action.icon = icon unless icon.null?
        action.on_triggered { on_outputs.call }
      end

      quit_action = Qt6::Action.new("Quit", window).tap do |action|
        icon = Qt6::QIcon.from_theme("application-exit")
        action.icon = icon unless icon.null?
        action.shortcut = "Ctrl+Q"
        action.on_triggered { on_quit.call }
      end

      app_menu.tap do |menu|
        menu.add_action(@about_action)
        menu.add_separator
        menu.add_action(@expanded_interface_action)
        menu.add_action(@blurred_cover_background_action)
        menu.add_separator
        menu.add_action(@show_main_menu_action)
        menu.add_separator
        menu.add_action(@settings_action)
        menu.add_menu(@outputs_menu)
        menu.add_separator
        menu.add_action(quit_action)
      end

      # Library menu

      library_menu = Qt6::Menu.new("&Library")

      @show_library_action = Qt6::Action.new("Show Library", window).tap do |action|
        icon = Qt6::QIcon.from_theme("view-list-tree")
        action.icon = icon unless icon.null?
        action.checkable = true
        action.checked = settings.show_library?
        action.on_toggled { |checked| on_show_library_changed.call(checked) }
      end

      @search_library_action = Qt6::Action.new("Search Library", window).tap do |action|
        icon = Qt6::QIcon.from_theme("edit-find")
        action.icon = icon unless icon.null?
        action.shortcut = "Ctrl+F"
        action.on_triggered { on_search_library.call }
      end

      @reload_database_action = Qt6::Action.new("Reload Database", window).tap do |action|
        icon = Qt6::QIcon.from_theme("view-refresh")
        action.icon = icon unless icon.null?
        action.shortcut = "F5"
        action.on_triggered { on_reload_database.call }
      end

      library_menu.tap do |menu|
        menu.add_action(@show_library_action)
        menu.add_separator
        menu.add_action(@search_library_action)
        menu.add_separator
        menu.add_action(@reload_database_action)
      end

      # Queue menu

      queue_menu = Qt6::Menu.new("&Queue")

      save_playlist_action = Qt6::Action.new("Save Queue as Playlist...", window).tap do |action|
        icon = Qt6::QIcon.from_theme("document-save")
        action.icon = icon unless icon.null?
        action.on_triggered { on_save_queue_as_playlist.call }
      end

      clear_action = Qt6::Action.new("Clear Queue", window).tap do |action|
        icon = Qt6::QIcon.from_theme("edit-clear")
        action.icon = icon unless icon.null?
        action.shortcut = "Ctrl+L"
        action.on_triggered { on_clear_queue.call }
      end

      queue_menu.tap do |menu|
        menu.add_action(save_playlist_action)
        menu.add_separator
        menu.add_action(clear_action)
      end

      # Menu builder
      menu_bar.add_menu(app_menu)
      menu_bar.add_menu(library_menu)
      menu_bar.add_menu(queue_menu)

      window.add_action(@show_main_menu_action)
      window.add_action(@settings_action)
      window.add_action(quit_action)
      window.add_action(@search_library_action)
      window.add_action(@reload_database_action)
      window.add_action(clear_action)
    end
  end
end
