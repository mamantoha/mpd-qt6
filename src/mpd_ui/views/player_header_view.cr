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
    getter play_icon : Qt6::QIcon = Qt6::QIcon.from_theme("media-playback-start")
    getter pause_icon : Qt6::QIcon = Qt6::QIcon.from_theme("media-playback-pause")
    getter stop_icon : Qt6::QIcon = Qt6::QIcon.from_theme("media-playback-stop")
    getter? dragging_progress : Bool = false

    property? syncing_progress : Bool = false
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
      actions : AppActions,
    )
      @root = Qt6::EventWidget.new(parent).tap do |widget|
        widget.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
      end

      @background = Qt6::Label.new("", @root).tap do |label|
        label.scaled_contents = true
        label.transparent_for_mouse_events = true
        label.visible = false

        blur = Qt6::GraphicsBlurEffect.new(label).tap do |effect|
          effect.blur_radius = 18
        end

        label.graphics_effect = blur
      end

      @cover_label = Qt6::Label.new("No Cover").tap do |label|
        label.set_fixed_size(cover_art_size, cover_art_size)
        label.scaled_contents = false
        label.alignment = Qt6::AlignmentFlag::Center
        label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Fixed)
        label.cursor_shape = Qt6::CursorShape::PointingHand
      end

      @title_label = Qt6::Label.new("Connecting...").tap do |label|
        label.style_sheet = "font-size: 16px; font-weight: bold;"
        label.word_wrap = true
        label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Minimum)
      end

      @subtitle_label = Qt6::Label.new("").tap do |label|
        label.word_wrap = true
        label.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Minimum)
      end

      @time_label = Qt6::Label.new("0:00 / 0:00").tap do |label|
        label.set_size_policy(Qt6::SizePolicy::Fixed, Qt6::SizePolicy::Fixed)
      end

      @previous_button = Qt6::PushButton.new("").tap do |button|
        button.icon_size = Qt6::Size.new(22, 22)
        button.icon = Qt6::QIcon.from_theme("media-skip-backward")
        button.fixed_width = 44
        button.tool_tip = "Previous"
        button.flat = true
        button.on_clicked { @on_previous.try(&.call) }
      end

      @play_pause_button = Qt6::PushButton.new("").tap do |button|
        button.icon_size = Qt6::Size.new(22, 22)
        button.icon = @play_icon
        button.fixed_width = 44
        button.tool_tip = "Play/Pause"
        button.flat = true
        button.on_clicked { @on_play_pause.try(&.call) }
      end

      @next_button = Qt6::PushButton.new("").tap do |button|
        button.icon_size = Qt6::Size.new(22, 22)
        button.icon = Qt6::QIcon.from_theme("media-skip-forward")
        button.fixed_width = 44
        button.tool_tip = "Next"
        button.flat = true
        button.on_clicked { @on_next.try(&.call) }
      end

      @shuffle_button = Qt6::PushButton.new("").tap do |button|
        button.icon_size = Qt6::Size.new(22, 22)
        button.icon = Qt6::QIcon.from_theme("media-playlist-shuffle")
        button.fixed_width = 44
        button.tool_tip = "Shuffle"
        button.flat = true
        button.checkable = true
        button.on_toggled { |checked| @on_shuffle_changed.try(&.call(checked)) }
      end

      @repeat_button = Qt6::PushButton.new("").tap do |button|
        button.icon_size = Qt6::Size.new(22, 22)
        button.icon = Qt6::QIcon.from_theme("media-playlist-repeat")
        button.fixed_width = 44
        button.tool_tip = "Repeat"
        button.flat = true
        button.checkable = true
        button.on_toggled { |checked| @on_repeat_changed.try(&.call(checked)) }
      end

      @volume_button = Qt6::PushButton.new("").tap do |button|
        button.icon_size = Qt6::Size.new(22, 22)
        button.icon = Qt6::QIcon.from_theme("audio-volume-medium")
        button.fixed_width = 44
        button.tool_tip = "Volume"
        button.style_sheet = "QPushButton::menu-indicator { image: none; width: 0px; }"
        button.flat = true
      end

      @progress_slider = Qt6::Slider.new(Qt6::Orientation::Horizontal).tap do |slider|
        slider.set_range(0, 1000)
        slider.value = 0
        slider.minimum_width = 320
        slider.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
        slider.click_to_position = true

        slider.on_pressed do
          @dragging_progress = true
        end

        slider.on_value_changed do |value|
          next if @syncing_progress || @duration <= 0

          @dragging_progress = true
          target = @duration * value / 1000.0
          @time_label.text = "#{Song.format_time(target)} / #{Song.format_time(@duration)}"
          show_progress_tooltip(slider_position_for_value(value), target)
        end

        slider.on_released do
          @dragging_progress = false
          next if @syncing_progress || @duration <= 0

          Qt6::ToolTip.hide_text
          target = @duration * slider.value / 1000.0
          @on_seek.try(&.call(target.to_i))
        end
      end

      @volume_slider = Qt6::Slider.new(Qt6::Orientation::Vertical).tap do |slider|
        slider.tool_tip = "Volume"
        slider.set_range(0, 100)
        slider.value = 0
        slider.set_fixed_size(36, 132)
        slider.enabled = false
        slider.click_to_position = true
        slider.on_value_changed { |value| @on_volume_changed.try(&.call(value)) }
      end

      @volume_label = Qt6::Label.new("--%").tap do |label|
        label.alignment = Qt6::AlignmentFlag::Center
        label.tool_tip = "Volume"
      end

      build(
        parent,
        cover_art_size,
        progress_row_height,
        playback_controls_height,
        actions
      )
    end

    def show_progress(elapsed : Float64, duration : Float64) : Nil
      @duration = duration
      pct = duration.positive? ? ((elapsed / duration) * 1000.0).clamp(0.0, 1000.0).round.to_i : 0
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
      actions : AppActions,
    ) : Nil
      setup_cover_art_toggle

      options_button = Qt6::PushButton.new("...").tap do |button|
        button.icon_size = Qt6::Size.new(22, 22)
        button.fixed_width = 44
        button.tool_tip = "Options"
        button.style_sheet = "QPushButton::menu-indicator { image: none; width: 0px; }"
        button.flat = true

        options_icon = Qt6::QIcon.from_theme("open-menu-symbolic")

        unless options_icon.null?
          button.icon = options_icon
          button.text = ""
        end
      end

      options_menu = Qt6::Menu.new("Options", options_button).tap do |menu|
        menu.add_action(actions.settings)
        menu.add_action(actions.outputs)
        menu.add_action(actions.search_library)
        menu.add_action(actions.reload_database)
        menu.add_separator
        menu.add_action(actions.show_library)
        menu.add_action(actions.expanded_interface)
        menu.add_action(actions.blurred_cover_background)
        menu.add_separator
        menu.add_action(actions.show_main_menu)
        menu.add_separator
        menu.add_action(actions.about)
      end

      options_button.menu = options_menu

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

        setup_progress_tooltip

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

        volume_menu = Qt6::Menu.new("Volume", @volume_button)
        volume_panel = Qt6::Widget.new(volume_menu)
        volume_widget_action = Qt6::WidgetAction.new(volume_menu)

        volume_panel.vbox do |volume_column|
          volume_column.set_contents_margins(8, 8, 8, 8)
          volume_column << @volume_slider
          volume_column << @volume_label
        end
        volume_widget_action.default_widget = volume_panel
        volume_menu.add_action(volume_widget_action)
        @volume_button.menu = volume_menu
        setup_volume_wheel(volume_menu, volume_panel)

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
      delta = wheel_event.pixel_delta.y if delta.zero?
      return false if delta.zero?

      step = delta.positive? ? 5 : -5
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
      x = width.positive? ? (width * value / 1000.0).clamp(0.0, width.to_f64) : 0.0
      Qt6::PointF.new(x, 0.0)
    end
  end
end
