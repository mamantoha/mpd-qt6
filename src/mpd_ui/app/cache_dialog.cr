module MPDUI
  module AppCacheDialog
    private def open_cache_dialog : Nil
      parent = @window
      return unless parent

      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = "Cached Items"
      dialog.resize(900, 520)

      title_label = Qt6::Label.new("Cached Items", dialog)
      title_label.style_sheet = "font-size: 18px; font-weight: bold;"

      description_label = Qt6::Label.new(
        "Garnetune caches covers, lyrics, and queued Last.fm scrobbles. Below is a summary of current cache usage.",
        dialog
      )
      description_label.word_wrap = true

      cache_table = Qt6::TableWidget.new(dialog)
      cache_table.column_count = 4
      cache_table.minimum_height = 340
      cache_table.selection_behavior = Qt6::ItemSelectionBehavior::SelectRows
      cache_table.edit_triggers = Qt6::EditTrigger::NoEditTriggers
      cache_table.alternating_row_colors = true
      cache_table.vertical_header.hide
      cache_table.set_horizontal_header_label(0, "Name")
      cache_table.set_horizontal_header_label(1, "Item Count")
      cache_table.set_horizontal_header_label(2, "Space Used")
      cache_table.set_horizontal_header_label(3, "Path")
      cache_table.horizontal_header.set_section_resize_mode(0, Qt6::HeaderResizeMode::ResizeToContents)
      cache_table.horizontal_header.set_section_resize_mode(1, Qt6::HeaderResizeMode::ResizeToContents)
      cache_table.horizontal_header.set_section_resize_mode(2, Qt6::HeaderResizeMode::ResizeToContents)
      cache_table.horizontal_header.set_section_resize_mode(3, Qt6::HeaderResizeMode::Stretch)

      total_label = Qt6::Label.new("", dialog)
      delete_button = Qt6::PushButton.new("Delete Selected", dialog)
      delete_button.enabled = false
      close_button = Qt6::PushButton.new("Close", dialog)
      button_row = Qt6::Widget.new(dialog)
      button_row.hbox do |row|
        row << total_label
        row.add_stretch
        row << delete_button
        row << close_button
      end

      entries = [] of CacheInfo::Entry
      refresh = -> do
        begin
          entries = CacheInfo.entries
          cache_table.clear_contents
          cache_table.row_count = entries.size

          entries.each_with_index do |entry, row|
            add_cache_table_item(cache_table, row, 0, entry.label)
            add_cache_table_item(cache_table, row, 1, entry.files.to_s)
            add_cache_table_item(cache_table, row, 2, format_cache_size(entry.bytes))
            add_cache_table_item(cache_table, row, 3, entry.path)
          end

          total_label.text = "Total space used: #{format_cache_size(entries.sum(&.bytes))}"
          delete_button.enabled = false
        rescue ex
          Log.warn { "mpd_ui: failed to refresh cache information: #{ex.message || ex}" }
          show_cache_dialog_message(dialog, "Cache Information Failed", ex.message || ex.to_s)
        end
      end

      cache_table.on_current_cell_changed do
        begin
          row = cache_table.current_row
          delete_button.enabled = row >= 0 && row < entries.size
        rescue ex
          Log.warn { "mpd_ui: failed to update cache selection: #{ex.message || ex}" }
        end
      end

      delete_button.on_clicked do
        begin
          row = cache_table.current_row
          next unless row >= 0 && row < entries.size

          entry = entries[row]
          next unless confirm_cache_delete(dialog, entry)

          CacheInfo.delete(entry)
          refresh.call
        rescue ex
          Log.warn { "mpd_ui: failed to delete cache: #{ex.message || ex}" }
          show_cache_dialog_message(dialog, "Delete Cache Failed", ex.message || ex.to_s)
        end
      end

      close_button.on_clicked { dialog.accept }

      refresh.call

      dialog.vbox do |column|
        column << title_label
        column << description_label
        column << cache_table
        column << button_row
      end

      dialog.exec
    ensure
      dialog.try(&.release)
    end

    private def add_cache_table_item(table : Qt6::TableWidget, row : Int32, column : Int32, text : String) : Nil
      item = Qt6::TableWidgetItem.new(text)
      item.flags = Qt6::ItemFlag::Selectable | Qt6::ItemFlag::Enabled
      item.tool_tip = text
      table.set_item(row, column, item)
    end

    private def confirm_cache_delete(parent : Qt6::Widget, entry : CacheInfo::Entry) : Bool
      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = "Delete Cache"

      title = Qt6::Label.new("Delete #{entry.label} cache?", dialog)
      title.style_sheet = "font-weight: bold;"

      path = Qt6::Label.new(entry.path, dialog)
      path.word_wrap = true

      delete_button = Qt6::PushButton.new("Delete", dialog)
      cancel_button = Qt6::PushButton.new("Cancel", dialog)
      delete_button.on_clicked { dialog.accept }
      cancel_button.on_clicked { dialog.reject }

      buttons = Qt6::Widget.new(dialog)
      buttons.hbox do |row|
        row.add_stretch
        row << delete_button
        row << cancel_button
      end

      dialog.vbox do |column|
        column << title
        column << path
        column << buttons
      end

      dialog.exec == Qt6::DialogCode::Accepted
    ensure
      dialog.try(&.release)
    end

    private def show_cache_dialog_message(parent : Qt6::Widget, title : String, text : String) : Nil
      dialog = Qt6::Dialog.new(parent)
      dialog.window_title = title

      label = Qt6::Label.new(text, dialog)
      label.word_wrap = true

      close_button = Qt6::PushButton.new("Close", dialog)
      close_button.on_clicked { dialog.accept }
      buttons = Qt6::Widget.new(dialog)
      buttons.hbox do |row|
        row.add_stretch
        row << close_button
      end

      dialog.vbox do |column|
        column << label
        column << buttons
      end

      dialog.exec
    ensure
      dialog.try(&.release)
    end

    private def format_cache_size(bytes : Int64) : String
      units = {"B", "KB", "MB", "GB"}
      value = bytes.to_f64
      unit = 0

      while value >= 1024 && unit < units.size - 1
        value /= 1024
        unit += 1
      end

      unit == 0 ? "#{bytes} B" : "#{value.round(1)} #{units[unit]}"
    end
  end
end
