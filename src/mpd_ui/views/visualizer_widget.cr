module MPDUI
  class VisualizerWidget
    HEIGHT = 34

    getter root : Qt6::EventWidget

    @timer : Qt6::QTimer
    @enabled : Bool = true

    def initialize(parent : Qt6::Widget, @service : VisualizerService)
      @root = Qt6::EventWidget.new(parent).tap do |widget|
        widget.fixed_height = HEIGHT
        widget.visible = false
        widget.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Fixed)
      end

      @root.on_paint_with_painter do |_event, painter|
        paint(painter)
      end

      @timer = Qt6::QTimer.new(@root)
      @timer.interval = 33
      @timer.on_timeout { refresh }
      @timer.start
    end

    def enabled=(value : Bool) : Bool
      @enabled = value
      refresh
      value
    end

    def enabled? : Bool
      @enabled
    end

    private def refresh : Nil
      visible = @enabled && @service.available?
      @root.visible = visible if @root.visible? != visible
      @root.update if visible
    end

    private def paint(painter : Qt6::QPainter) : Nil
      levels = @service.levels
      return if levels.empty?

      width = @root.width.to_f
      height = @root.height.to_f
      return unless width.positive? && height.positive?

      painter.antialiasing = true
      no_pen = Qt6::QPen.new(Qt6::Color.new(0, 0, 0, 0), 0).tap(&.style=(Qt6::PenStyle::NoPen))
      palette = @root.palette
      begin
        painter.pen = no_pen
        shadow_color = palette_color(palette, Qt6::ColorRole::Shadow, 90)
        highlight_color = palette_color(palette, Qt6::ColorRole::Highlight)

        gap = 2.0
        bar_width = {1.0, (width - gap * (levels.size - 1)) / levels.size}.max

        levels.each_with_index do |level, index|
          bar_height = (level * height).clamp(1.0, height)
          x = index * (bar_width + gap)
          y = height - bar_height

          painter.brush = shadow_color
          painter.draw_rounded_rect(Qt6::RectF.new(x, y + 1.0, bar_width, bar_height), 2.0, 2.0)
          painter.brush = highlight_color
          painter.draw_rounded_rect(Qt6::RectF.new(x, y, bar_width, bar_height), 2.0, 2.0)
        end
      ensure
        palette.release
        no_pen.release
      end
    end

    private def palette_color(palette : Qt6::QPalette, role : Qt6::ColorRole, alpha : Int32 = 255) : Qt6::Color
      color = palette.color(role)
      Qt6::Color.new(color.red, color.green, color.blue, alpha)
    end
  end
end
