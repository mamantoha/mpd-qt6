require "json"

module MPDUI
  module TwoLineItemDelegate
    def self.build(parent : Qt6::Widget, model : Qt6::AbstractItemModel) : Qt6::StyledItemDelegate
      delegate = Qt6::StyledItemDelegate.new(parent)
      delegate.on_paint do |painter, option, index|
        payload = parse_payload(index.data(model).as?(String))
        next false unless payload

        title = payload["title"].not_nil!
        subtitle = payload["subtitle"]?

        option.draw_background(painter)
        option.draw_decoration(painter)

        rect = option.text_rect
        title_font = option.font
        title_font.bold = true
        subtitle_font = option.font
        if subtitle_font.point_size.positive?
          subtitle_font.point_size = Math.max(1, (subtitle_font.point_size * 0.86).round.to_i)
        end

        title_metrics = title_font.metrics
        subtitle_metrics = subtitle_font.metrics
        title_height = title_metrics.height
        subtitle_height = subtitle_metrics.height
        text_height = subtitle && !subtitle.empty? ? title_height + subtitle_height : title_height
        top = rect.y + Math.max(0.0, (rect.height - text_height) / 2.0)

        palette = option.palette
        title_color = option.selected? ? palette.color(Qt6::ColorRole::HighlightedText) : palette.color(Qt6::ColorRole::Text)
        subtitle_color = option.selected? ? title_color : palette.color(Qt6::ColorGroup::Disabled, Qt6::ColorRole::Text)

        painter.save
        painter.font = title_font
        painter.pen = title_color
        painter.draw_text(Qt6::RectF.new(rect.x, top, rect.width, title_height.to_f64), Qt6::AlignmentFlag::Left | Qt6::AlignmentFlag::VCenter, title)
        if subtitle && !subtitle.empty?
          painter.font = subtitle_font
          painter.pen = subtitle_color
          painter.draw_text(Qt6::RectF.new(rect.x, top + title_height, rect.width, subtitle_height.to_f64), Qt6::AlignmentFlag::Left | Qt6::AlignmentFlag::VCenter, subtitle)
        end
        painter.restore
        true
      end
      delegate.on_size_hint do |_option, index|
        payload = parse_payload(index.data(model).as?(String))
        subtitle = payload.try(&.["subtitle"]?)
        subtitle && !subtitle.empty? ? Qt6::Size.new(0, 42) : nil
      end
      delegate
    end

    def self.payload(title : String, subtitle : String? = nil, **extra) : String
      JSON.build do |json|
        json.object do
          json.field "title", title
          json.field "subtitle", subtitle if subtitle
          extra.each do |key, value|
            next unless value

            json.field key.to_s, value
          end
        end
      end
    end

    def self.parse_payload(value : String?) : Hash(String, String)?
      return unless value

      json = JSON.parse(value)
      title = json["title"]?.try(&.as_s?)
      return unless title

      payload = {"title" => title}
      json.as_h.each do |key, item|
        next if key == "title"

        if string = item.as_s?
          payload[key] = string
        end
      end
      payload
    rescue JSON::ParseException
      nil
    end
  end
end
