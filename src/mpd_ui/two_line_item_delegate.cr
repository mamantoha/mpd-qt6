module MPDUI
  module TwoLineItemDelegate
    ICON_SIZE    = 24
    ICON_SPACING =  8

    @@icons = {} of String => Qt6::QIcon

    def self.build(parent : Qt6::Widget, model : Qt6::AbstractItemModel) : Qt6::StyledItemDelegate
      delegate = Qt6::StyledItemDelegate.new(parent)
      delegate.on_paint do |painter, option, index|
        title = index.data(model, ItemRoles::TITLE).as?(String)
        next false unless title

        subtitle = index.data(model, ItemRoles::SUBTITLE).as?(String)
        icon_kind = index.data(model, ItemRoles::ICON_KIND).as?(String)

        option.draw_background(painter)
        draw_icon(painter, option, icon_kind)

        rect = text_rect(option, icon_kind)
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
        subtitle = index.data(model, ItemRoles::SUBTITLE).as?(String)
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
      item.set_data(title, ItemRoles::TITLE)
      item.set_data(subtitle || "", ItemRoles::SUBTITLE)
      item
    end

    private def self.text_rect(option : Qt6::StyleOptionViewItem, icon_kind : String?) : Qt6::RectF
      rect = option.text_rect
      return rect unless icon_kind && !icon_kind.empty?

      offset = ICON_SIZE + ICON_SPACING
      Qt6::RectF.new(rect.x + offset, rect.y, Math.max(0.0, rect.width - offset), rect.height)
    end

    private def self.draw_icon(painter : Qt6::QPainter, option : Qt6::StyleOptionViewItem, icon_kind : String?) : Nil
      return unless icon_kind && !icon_kind.empty?

      rect = option.text_rect
      icon_rect = Qt6::RectF.new(rect.x, rect.y + Math.max(0.0, (rect.height - ICON_SIZE) / 2.0), ICON_SIZE.to_f64, ICON_SIZE.to_f64)
      icon = icon_for(icon_kind)

      if icon && !icon.null?
        icon.paint(painter, icon_rect)
      end
    end

    private def self.icon_for(kind : String) : Qt6::QIcon?
      cached = @@icons[kind]?
      return cached if cached

      icon = icon_names(kind).compact_map do |name|
        candidate = Qt6::QIcon.from_theme(name)
        candidate.null? ? nil : candidate
      end.first?
      icon ||= Qt6::QIcon.new
      @@icons[kind] = icon
      icon
    end

    private def self.icon_names(kind : String) : Array(String)
      case kind
      when "artist"   then ["user-identity", "avatar-default", "contact-new"]
      when "album"    then ["media-optical-audio", "media-optical"]
      when "song"     then ["audio-x-generic", "audio-mpeg"]
      when "playlist" then ["view-media-playlist", "format-list-unordered"]
      else
        [] of String
      end
    end
  end
end
