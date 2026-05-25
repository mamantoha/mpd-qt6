module MPDUI
  class ApplicationMenu
    def initialize(window : Qt6::MainWindow, actions : AppActions)
      menu_bar = window.menu_bar

      app_menu = Qt6::Menu.new("&App")
      app_menu.add_action(actions.about)
      app_menu.add_separator
      app_menu.add_action(actions.expanded_interface)
      app_menu.add_action(actions.blurred_cover_background)
      app_menu.add_separator
      app_menu.add_action(actions.show_main_menu)
      app_menu.add_separator
      app_menu.add_action(actions.settings)
      app_menu.add_menu(actions.outputs_menu)
      app_menu.add_separator
      app_menu.add_action(actions.quit)

      library_menu = Qt6::Menu.new("&Library")
      library_menu.add_action(actions.show_library)
      library_menu.add_separator
      library_menu.add_action(actions.search_library)
      library_menu.add_separator
      library_menu.add_action(actions.reload_database)

      queue_menu = Qt6::Menu.new("&Queue")
      queue_menu.add_action(actions.save_queue_as_playlist)
      queue_menu.add_separator
      queue_menu.add_action(actions.clear_queue)

      menu_bar.add_menu(app_menu)
      menu_bar.add_menu(library_menu)
      menu_bar.add_menu(queue_menu)

      window.add_action(actions.show_main_menu)
      window.add_action(actions.settings)
      window.add_action(actions.quit)
      window.add_action(actions.search_library)
      window.add_action(actions.reload_database)
      window.add_action(actions.clear_queue)
    end
  end
end
