module MPDUI
  class PlayerHeaderView
    getter root : Qt6::EventWidget
    getter background : Qt6::Label
    getter cover_label : Qt6::Label
    getter title_label : Qt6::Label
    getter subtitle_label : Qt6::Label
    getter time_label : Qt6::Label
    getter previous_button : Qt6::PushButton
    getter play_pause_button : Qt6::PushButton
    getter next_button : Qt6::PushButton
    getter shuffle_button : Qt6::PushButton
    getter repeat_button : Qt6::PushButton
    getter progress_slider : Qt6::Slider
    getter volume_button : Qt6::PushButton
    getter volume_slider : Qt6::Slider
    getter volume_label : Qt6::Label
    getter play_icon : Qt6::QIcon
    getter pause_icon : Qt6::QIcon
    getter stop_icon : Qt6::QIcon
    getter? dragging_progress : Bool = false

    property syncing_progress : Bool = false
    property duration : Float64 = 0.0
    property on_previous : Proc(Nil)?
    property on_play_pause : Proc(Nil)?
    property on_next : Proc(Nil)?
    property on_shuffle_changed : Proc(Bool, Nil)?
    property on_repeat_changed : Proc(Bool, Nil)?
    property on_volume_changed : Proc(Int32, Nil)?
    property on_seek : Proc(Int32, Nil)?
    property on_cover_clicked : Proc(Nil)?

    @progress_tooltip_filter : Qt6::EventFilter?
    @cover_click_filter : Qt6::EventFilter?
    @volume_wheel_filter : Qt6::EventFilter?
    @volume_menu_wheel_filter : Qt6::EventFilter?
    @volume_panel_wheel_filter : Qt6::EventFilter?

    def initialize(
      parent : Qt6::Widget,
      cover_art_size : Int32,
      progress_row_height : Int32,
      playback_controls_height : Int32,
      settings_action : Qt6::Action? = nil,
      search_library_action : Qt6::Action? = nil,
      reload_database_action : Qt6::Action? = nil,
      show_library_action : Qt6::Action? = nil,
      expanded_interface_action : Qt6::Action? = nil,
      blurred_cover_background_action : Qt6::Action? = nil,
      show_main_menu_action : Qt6::Action? = nil,
      about_action : Qt6::Action? = nil,
    )
      @root = Qt6::EventWidget.new(parent)
      @background = Qt6::Label.new("", @root)
      @cover_label = Qt6::Label.new("No Cover")
      @title_label = Qt6::Label.new("Connecting...")
      @subtitle_label = Qt6::Label.new("")
      @time_label = Qt6::Label.new("0:00 / 0:00")
      @previous_button = Qt6::PushButton.new("")
      @play_pause_button = Qt6::PushButton.new("")
      @next_button = Qt6::PushButton.new("")
      @shuffle_button = Qt6::PushButton.new("")
      @repeat_button = Qt6::PushButton.new("")
      @progress_slider = Qt6::Slider.new(Qt6::Orientation::Horizontal)
      @volume_button = Qt6::PushButton.new("")
      @volume_slider = Qt6::Slider.new(Qt6::Orientation::Vertical)
      @volume_label = Qt6::Label.new("--%")
      @play_icon = Qt6::QIcon.from_theme("media-playback-start")
      @pause_icon = Qt6::QIcon.from_theme("media-playback-pause")
      @stop_icon = Qt6::QIcon.from_theme("media-playback-stop")

      build(
        parent,
        cover_art_size,
        progress_row_height,
        playback_controls_height,
        settings_action,
        search_library_action,
        reload_database_action,
        show_library_action,
        expanded_interface_action,
        blurred_cover_background_action,
        show_main_menu_action,
        about_action
      )
    end

    def show_progress(elapsed : Float64, duration : Float64) : Nil
      @duration = duration
      pct = duration > 0 ? ((elapsed / duration) * 1000.0).clamp(0.0, 1000.0).round.to_i : 0
      @syncing_progress = true
      @progress_slider.value = pct
      @time_label.text = "#{Song.format_time(elapsed)} / #{Song.format_time(duration)}"
      @syncing_progress = false
    end

    def cancel_progress_drag : Nil
      @dragging_progress = false
    end

    private def build(
      parent : Qt6::Widget,
      cover_art_size : Int32,
      progress_row_height : Int32,
      playback_controls_height : Int32,
      settings_action : Qt6::Action?,
      search_library_action : Qt6::Action?,
      reload_database_action : Qt6::Action?,
      show_library_action : Qt6::Action?,
      expanded_interface_action : Qt6::Action?,
      blurred_cover_background_action : Qt6::Action?,
      show_main_menu_action : Qt6::Action?,
      about_action : Qt6::Action?,
    ) : Nil
      @cover_label.set_fixed_size(cover_art_size, cover_art_size)
      @cover_label.scaled_contents = false
      @cover_label.alignment = Qt6::AlignmentFlag::Center
      @cover_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Fixed)
      @cover_label.cursor_shape = Qt6::CursorShape::PointingHand
      setup_cover_art_toggle

      options_button = Qt6::PushButton.new("...")
      options_menu = Qt6::Menu.new("Options", options_button)
      options_icon = Qt6::QIcon.from_theme("open-menu-symbolic")
      unless options_icon.null?
        options_button.icon = options_icon
        options_button.text = ""
      end
      options_button.icon_size = Qt6::Size.new(22, 22)
      options_button.fixed_width = 44
      options_button.tool_tip = "Options"
      options_button.style_sheet = "QPushButton::menu-indicator { image: none; width: 0px; }"
      options_button.flat = true
      add_action_if_present(options_menu, settings_action)
      add_action_if_present(options_menu, search_library_action)
      add_action_if_present(options_menu, reload_database_action)
      options_menu.add_separator
      add_action_if_present(options_menu, show_library_action)
      add_action_if_present(options_menu, expanded_interface_action)
      add_action_if_present(options_menu, blurred_cover_background_action)
      options_menu.add_separator
      add_action_if_present(options_menu, show_main_menu_action)
      options_menu.add_separator
      add_action_if_present(options_menu, about_action)
      options_button.menu = options_menu

      @title_label.style_sheet = "font-size: 16px; font-weight: bold;"
      @title_label.word_wrap = true
      @title_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Minimum)
      @subtitle_label.word_wrap = true
      @subtitle_label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Minimum)

      progress = build_progress(parent, progress_row_height)
      controls = build_controls(parent, playback_controls_height)

      metadata_panel = Qt6::Widget.new(parent)
      metadata_panel.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
      metadata_panel.vbox do |metadata_column|
        metadata_column.spacing = 2
        metadata_column.set_contents_margins(0, 0, 0, 0)
        metadata_column << @title_label
        metadata_column << @subtitle_label
      end

      options_panel = Qt6::Widget.new(parent)
      options_panel.set_size_policy(Qt6::SizePolicy::Fixed, Qt6::SizePolicy::Preferred)
      options_panel.vbox do |options_column|
        options_column.set_contents_margins(0, 0, 0, 0)
        options_column << options_button
        options_column.add_stretch
      end

      header_body = Qt6::Widget.new(parent)
      header_body.fixed_height = cover_art_size
      header_body.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
      header_body.grid do |grid|
        grid.spacing = 10
        grid.set_contents_margins(0, 0, 0, 0)
        grid.add(@cover_label, 0, 0, 2, 1)
        grid.add(metadata_panel, 0, 1)
        grid.add(options_panel, 0, 2)
        grid.add(progress, 1, 1, 1, 2)
      end

      @root.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
      @background.scaled_contents = true
      @background.transparent_for_mouse_events = true
      @background.visible = false
      blur = Qt6::GraphicsBlurEffect.new(@background)
      blur.blur_radius = 18
      @background.graphics_effect = blur

      content = Qt6::Widget.new(@root)
      content.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
      content.vbox do |header_column|
        header_column.spacing = 8
        header_column.set_contents_margins(8, 8, 8, 8)
        header_column << header_body
        header_column << controls
      end

      @root.vbox do |header_column|
        header_column.set_contents_margins(0, 0, 0, 0)
        header_column << content
      end
      @root.on_resize do |event|
        @background.resize(event.size.width, event.size.height)
        @background.move(0, 0)
        content.raise_to_front
      end
      content.raise_to_front
    end

    private def build_progress(parent : Qt6::Widget, progress_row_height : Int32) : Qt6::Widget
      progress = Qt6::Widget.new(parent)
      progress.fixed_height = progress_row_height
      progress.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
      progress.hbox do |row|
        row.spacing = 6
        row.set_contents_margins(0, 0, 0, 0)

        @progress_slider.set_range(0, 1000)
        @progress_slider.value = 0
        @progress_slider.minimum_width = 320
        @progress_slider.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
        @progress_slider.click_to_position = true
        setup_progress_tooltip

        @time_label.set_size_policy(Qt6::SizePolicy::Fixed, Qt6::SizePolicy::Fixed)

        @progress_slider.on_pressed do
          @dragging_progress = true
        end

        @progress_slider.on_value_changed do |value|
          next if @syncing_progress || @duration <= 0

          @dragging_progress = true
          target = @duration * value / 1000.0
          @time_label.text = "#{Song.format_time(target)} / #{Song.format_time(@duration)}"
          show_progress_tooltip(slider_position_for_value(value), target)
        end

        @progress_slider.on_released do
          @dragging_progress = false
          next if @syncing_progress || @duration <= 0

          Qt6::ToolTip.hide_text
          target = @duration * @progress_slider.value / 1000.0
          @on_seek.try(&.call(target.to_i))
        end

        row << @progress_slider
        row << @time_label
      end
      progress
    end

    private def build_controls(parent : Qt6::Widget, playback_controls_height : Int32) : Qt6::Widget
      controls = Qt6::Widget.new(parent)
      controls.fixed_height = playback_controls_height
      controls.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Fixed)
      controls.hbox do |row|
        row.spacing = 6
        row.set_contents_margins(0, 0, 0, 0)

        prev_icon = Qt6::QIcon.from_theme("media-skip-backward")
        next_icon = Qt6::QIcon.from_theme("media-skip-forward")
        shuffle_icon = Qt6::QIcon.from_theme("media-playlist-shuffle")
        repeat_icon = Qt6::QIcon.from_theme("media-playlist-repeat")
        volume_icon = Qt6::QIcon.from_theme("audio-volume-medium")

        @previous_button.icon = prev_icon
        @play_pause_button.icon = @play_icon
        @next_button.icon = next_icon
        @shuffle_button.icon = shuffle_icon unless shuffle_icon.null?
        @repeat_button.icon = repeat_icon unless repeat_icon.null?
        @volume_button.icon = volume_icon unless volume_icon.null?
        [@previous_button, @play_pause_button, @next_button, @shuffle_button, @repeat_button, @volume_button].each do |button|
          button.icon_size = Qt6::Size.new(22, 22)
          button.fixed_width = 44
          button.flat = true
        end

        @previous_button.tool_tip = "Previous"
        @play_pause_button.tool_tip = "Play/Pause"
        @next_button.tool_tip = "Next"
        @shuffle_button.tool_tip = "Shuffle"
        @repeat_button.tool_tip = "Repeat"
        @volume_button.tool_tip = "Volume"
        @volume_button.style_sheet = "QPushButton::menu-indicator { image: none; width: 0px; }"

        volume_menu = Qt6::Menu.new("Volume", @volume_button)
        volume_panel = Qt6::Widget.new(volume_menu)
        volume_widget_action = Qt6::WidgetAction.new(volume_menu)
        @volume_slider.tool_tip = "Volume"
        @volume_slider.set_range(0, 100)
        @volume_slider.value = 0
        @volume_slider.set_fixed_size(36, 132)
        @volume_slider.enabled = false
        @volume_slider.click_to_position = true
        @volume_label.alignment = Qt6::AlignmentFlag::Center
        @volume_label.tool_tip = "Volume"
        volume_panel.vbox do |volume_column|
          volume_column.set_contents_margins(8, 8, 8, 8)
          volume_column << @volume_slider
          volume_column << @volume_label
        end
        volume_widget_action.default_widget = volume_panel
        volume_menu.add_action(volume_widget_action)
        @volume_button.menu = volume_menu
        setup_volume_wheel(volume_menu, volume_panel)

        @shuffle_button.checkable = true
        @repeat_button.checkable = true

        @previous_button.on_clicked { @on_previous.try(&.call) }
        @play_pause_button.on_clicked { @on_play_pause.try(&.call) }
        @next_button.on_clicked { @on_next.try(&.call) }
        @shuffle_button.on_toggled { |checked| @on_shuffle_changed.try(&.call(checked)) }
        @repeat_button.on_toggled { |checked| @on_repeat_changed.try(&.call(checked)) }
        @volume_slider.on_value_changed { |value| @on_volume_changed.try(&.call(value)) }

        row.add_stretch
        row << @previous_button
        row << @play_pause_button
        row << @next_button
        row << @shuffle_button
        row << @repeat_button
        row << @volume_button
        row.add_stretch
      end
      controls
    end

    private def add_action_if_present(menu : Qt6::Menu, action : Qt6::Action?) : Nil
      menu.add_action(action) if action
    end

    private def setup_cover_art_toggle : Nil
      filter = Qt6::EventFilter.new(@cover_label)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseButtonRelease
          mouse_event = event.mouse_event
          if mouse_event.button == 1
            Qt6::ToolTip.hide_text
            @on_cover_clicked.try(&.call)
            true
          else
            false
          end
        else
          false
        end
      end

      @cover_label.install_event_filter(filter)
      @cover_click_filter = filter
    end

    private def setup_volume_wheel(volume_menu : Qt6::Menu, volume_panel : Qt6::Widget) : Nil
      filter = Qt6::EventFilter.new(@volume_button)
      filter.on_event do |_watched, event|
        next false unless event.type == Qt6::EventType::Wheel

        change_volume_from_wheel(event)
      end

      @volume_button.install_event_filter(filter)
      @volume_wheel_filter = filter

      menu_filter = Qt6::EventFilter.new(volume_menu)
      menu_filter.on_event do |_watched, event|
        next false unless event.type == Qt6::EventType::Wheel

        change_volume_from_wheel(event)
      end
      volume_menu.install_event_filter(menu_filter)
      @volume_menu_wheel_filter = menu_filter

      panel_filter = Qt6::EventFilter.new(volume_panel)
      panel_filter.on_event do |_watched, event|
        next false unless event.type == Qt6::EventType::Wheel

        change_volume_from_wheel(event)
      end
      volume_panel.install_event_filter(panel_filter)
      @volume_panel_wheel_filter = panel_filter
    end

    private def change_volume_from_wheel(event : Qt6::QEvent) : Bool
      return false unless @volume_slider.enabled?

      wheel_event = event.wheel_event
      delta = wheel_event.angle_delta.y
      delta = wheel_event.pixel_delta.y if delta == 0.0
      return false if delta == 0.0

      step = delta > 0.0 ? 5 : -5
      @volume_slider.value = (@volume_slider.value + step).clamp(0, 100)
      event.accept
      true
    end

    private def setup_progress_tooltip : Nil
      @progress_slider.mouse_tracking = true

      filter = Qt6::EventFilter.new(@progress_slider)
      filter.on_event do |_watched, event|
        case event.type
        when Qt6::EventType::MouseMove
          show_progress_tooltip(event.mouse_event.position)
          false
        when Qt6::EventType::Leave
          @dragging_progress = false
          @progress_slider.tool_tip = ""
          Qt6::ToolTip.hide_text
          false
        else
          false
        end
      end

      @progress_slider.install_event_filter(filter)
      @progress_tooltip_filter = filter
    end

    private def show_progress_tooltip(position : Qt6::PointF, seconds : Float64? = nil) : Nil
      if @duration <= 0
        @progress_slider.tool_tip = ""
        Qt6::ToolTip.hide_text
        return
      end

      width = @progress_slider.size.width
      return if width <= 0

      x = position.x.clamp(0.0, width.to_f64)
      target = seconds || (@duration * x / width)
      text = Song.format_time(target)
      @progress_slider.tool_tip = text
      Qt6::ToolTip.show_text(@progress_slider, Qt6::PointF.new(x, 0.0), text)
    end

    private def slider_position_for_value(value : Int32) : Qt6::PointF
      width = @progress_slider.size.width
      x = width > 0 ? (width * value / 1000.0).clamp(0.0, width.to_f64) : 0.0
      Qt6::PointF.new(x, 0.0)
    end
  end
end
