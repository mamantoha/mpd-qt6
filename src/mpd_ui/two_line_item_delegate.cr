module MPDUI
  module TwoLineItemDelegate
    TITLE_ROLE = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 1)
    SUBTITLE_ROLE = Qt6::ItemDataRole.new(Qt6::ItemDataRole::User.value + 2)

    def self.build(parent : Qt6::Widget, model : Qt6::AbstractItemModel) : Qt6::StyledItemDelegate
      delegate = Qt6::StyledItemDelegate.new(parent)
      delegate.on_paint do |painter, option, index|
        title = index.data(model, TITLE_ROLE).as?(String)
        next false unless title

        subtitle = index.data(model, SUBTITLE_ROLE).as?(String)

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
        subtitle = index.data(model, SUBTITLE_ROLE).as?(String)
        subtitle && !subtitle.empty? ? Qt6::Size.new(0, 42) : nil
      end
      delegate
    end

    def self.item(title : String, subtitle : String? = nil) : Qt6::StandardItem
      item = Qt6::StandardItem.new(title)
      configure(item, title, subtitle)
      item
    end

    def self.configure(item : Qt6::StandardItem, title : String, subtitle : String? = nil) : Qt6::StandardItem
      item.set_data(title, TITLE_ROLE)
      item.set_data(subtitle || "", SUBTITLE_ROLE)
      item
    end
  end
end
