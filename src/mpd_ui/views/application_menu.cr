module MPDUI
  class ApplicationMenu
    getter about_action : Qt6::Action
    getter settings_action : Qt6::Action
    getter search_library_action : Qt6::Action
    getter reload_database_action : Qt6::Action
    getter expanded_interface_action : Qt6::Action
    getter show_library_action : Qt6::Action
    getter show_main_menu_action : Qt6::Action
    getter blurred_cover_background_action : Qt6::Action

    def initialize(
      window : Qt6::MainWindow,
      settings : Settings,
      on_about : ->,
      on_expanded_interface_changed : Bool ->,
      on_blurred_cover_background_changed : Bool ->,
      on_settings : ->,
      on_quit : ->,
      on_show_library_changed : Bool ->,
      on_search_library : ->,
      on_reload_database : ->,
      on_clear_queue : ->
    )
      menu_bar = window.menu_bar

      app_menu = menu_bar.add_menu("&App")
      @about_action = Qt6::Action.new("About", window)
      about_icon = Qt6::QIcon.from_theme("help-about")
      @about_action.icon = about_icon unless about_icon.null?
      @about_action.on_triggered { on_about.call }
      app_menu.add_action(@about_action)
      app_menu.add_separator

      @expanded_interface_action = Qt6::Action.new("Expanded Interface", window)
      expanded_interface_icon = Qt6::QIcon.from_theme("view-fullscreen")
      @expanded_interface_action.icon = expanded_interface_icon unless expanded_interface_icon.null?
      @expanded_interface_action.checkable = true
      @expanded_interface_action.checked = settings.expanded_interface
      @expanded_interface_action.on_toggled { |checked| on_expanded_interface_changed.call(checked) }
      app_menu.add_action(@expanded_interface_action)

      @blurred_cover_background_action = Qt6::Action.new("Blurred Cover Background", window)
      blurred_cover_icon = Qt6::QIcon.from_theme("image-x-generic")
      @blurred_cover_background_action.icon = blurred_cover_icon unless blurred_cover_icon.null?
      @blurred_cover_background_action.checkable = true
      @blurred_cover_background_action.checked = settings.blurred_cover_background
      @blurred_cover_background_action.on_toggled { |checked| on_blurred_cover_background_changed.call(checked) }
      app_menu.add_action(@blurred_cover_background_action)
      app_menu.add_separator

      @show_main_menu_action = Qt6::Action.new("Show Main Menu", window)
      main_menu_icon = Qt6::QIcon.from_theme("show-menu")
      @show_main_menu_action.icon = main_menu_icon unless main_menu_icon.null?
      @show_main_menu_action.checkable = true
      @show_main_menu_action.checked = settings.show_main_menu
      @show_main_menu_action.shortcut = "Ctrl+M"
      @show_main_menu_action.on_toggled do |checked|
        window.menu_bar.visible = checked
        if settings.show_main_menu != checked
          settings.show_main_menu = checked
          settings.save
        end
      end
      app_menu.add_action(@show_main_menu_action)
      window.add_action(@show_main_menu_action)
      window.menu_bar.visible = settings.show_main_menu
      app_menu.add_separator

      @settings_action = Qt6::Action.new("Settings", window)
      settings_icon = Qt6::QIcon.from_theme("preferences-system")
      @settings_action.icon = settings_icon unless settings_icon.null?
      @settings_action.shortcut = "Ctrl+,"
      @settings_action.on_triggered { on_settings.call }
      app_menu.add_action(@settings_action)
      window.add_action(@settings_action)
      app_menu.add_separator

      quit_action = Qt6::Action.new("Quit", window)
      quit_icon = Qt6::QIcon.from_theme("application-exit")
      quit_action.icon = quit_icon unless quit_icon.null?
      quit_action.shortcut = "Ctrl+Q"
      quit_action.on_triggered { on_quit.call }
      app_menu.add_action(quit_action)
      window.add_action(quit_action)

      library_menu = menu_bar.add_menu("&Library")
      @show_library_action = Qt6::Action.new("Show Library", window)
      library_icon = Qt6::QIcon.from_theme("view-list-tree")
      @show_library_action.icon = library_icon unless library_icon.null?
      @show_library_action.checkable = true
      @show_library_action.checked = settings.show_library
      @show_library_action.on_toggled { |checked| on_show_library_changed.call(checked) }
      library_menu.add_action(@show_library_action)
      library_menu.add_separator

      @search_library_action = Qt6::Action.new("Search Library", window)
      search_icon = Qt6::QIcon.from_theme("edit-find")
      @search_library_action.icon = search_icon unless search_icon.null?
      @search_library_action.shortcut = "Ctrl+F"
      @search_library_action.on_triggered { on_search_library.call }
      library_menu.add_action(@search_library_action)
      window.add_action(@search_library_action)
      library_menu.add_separator

      @reload_database_action = Qt6::Action.new("Reload Database", window)
      reload_icon = Qt6::QIcon.from_theme("view-refresh")
      @reload_database_action.icon = reload_icon unless reload_icon.null?
      @reload_database_action.shortcut = "F5"
      @reload_database_action.on_triggered { on_reload_database.call }
      library_menu.add_action(@reload_database_action)
      window.add_action(@reload_database_action)

      queue_menu = menu_bar.add_menu("&Queue")
      clear_action = Qt6::Action.new("Clear Queue", window)
      clear_icon = Qt6::QIcon.from_theme("edit-clear")
      clear_action.icon = clear_icon unless clear_icon.null?
      clear_action.shortcut = "Ctrl+L"
      clear_action.on_triggered { on_clear_queue.call }
      queue_menu.add_action(clear_action)
      window.add_action(clear_action)
    end
  end
end
