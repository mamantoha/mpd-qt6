module MPDUI
  class AppActions
    getter about : Qt6::Action
    getter settings : Qt6::Action
    getter outputs : Qt6::Action
    getter outputs_menu : Qt6::Menu
    getter quit : Qt6::Action
    getter show_library : Qt6::Action
    getter show_lyrics : Qt6::Action
    getter search_library : Qt6::Action
    getter reload_database : Qt6::Action
    getter expanded_interface : Qt6::Action
    getter blurred_cover_background : Qt6::Action
    getter show_main_menu : Qt6::Action
    getter save_queue_as_playlist : Qt6::Action
    getter clear_queue : Qt6::Action

    def initialize(window : Qt6::MainWindow, settings : Settings)
      @about = Qt6::Action.new("About", window).tap do |action|
        set_icon(action, "help-about")
      end

      @settings = Qt6::Action.new("Settings", window).tap do |action|
        set_icon(action, "preferences-system")
        action.shortcut = "Ctrl+,"
      end

      @outputs_menu = Qt6::Menu.new("Outputs", window)
      @outputs = @outputs_menu.menu_action.tap do |action|
        set_icon(action, "audio-speakers")
      end

      @quit = Qt6::Action.new("Quit", window).tap do |action|
        set_icon(action, "application-exit")
        action.shortcut = "Ctrl+Q"
      end

      @show_library = Qt6::Action.new("Show Library", window).tap do |action|
        set_icon(action, "view-list-tree")
        action.checkable = true
        action.checked = settings.show_library?
      end

      @show_lyrics = Qt6::Action.new("Show Lyrics", window).tap do |action|
        set_icon(action, "text-x-generic")
        action.checkable = true
        action.checked = settings.show_lyrics?
      end

      @search_library = Qt6::Action.new("Search Library", window).tap do |action|
        set_icon(action, "edit-find")
        action.shortcut = "Ctrl+F"
      end

      @reload_database = Qt6::Action.new("Reload Database", window).tap do |action|
        set_icon(action, "view-refresh")
        action.shortcut = "F5"
      end

      @expanded_interface = Qt6::Action.new("Expanded Interface", window).tap do |action|
        set_icon(action, "view-fullscreen")
        action.checkable = true
        action.checked = settings.expanded_interface?
      end

      @blurred_cover_background = Qt6::Action.new("Blurred Cover Background", window).tap do |action|
        set_icon(action, "image-x-generic")
        action.checkable = true
        action.checked = settings.blurred_cover_background?
      end

      @show_main_menu = Qt6::Action.new("Show Main Menu", window).tap do |action|
        set_icon(action, "show-menu")
        action.checkable = true
        action.checked = settings.show_main_menu?
        action.shortcut = "Ctrl+M"
      end

      @save_queue_as_playlist = Qt6::Action.new("Save Queue as Playlist...", window).tap do |action|
        set_icon(action, "document-save")
      end

      @clear_queue = Qt6::Action.new("Clear Queue", window).tap do |action|
        set_icon(action, "edit-clear")
        action.shortcut = "Ctrl+L"
      end
    end

    private def set_icon(action : Qt6::Action, icon_name : String) : Nil
      icon = Qt6::QIcon.from_theme(icon_name)
      action.icon = icon unless icon.null?
    end
  end
end
