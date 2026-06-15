module MPDUI
  class AppLayoutView
    getter central : Qt6::Widget
    getter player_header : PlayerHeaderView
    getter browsers : Qt6::Splitter
    getter compact_spacer : Qt6::Widget
    getter database_panel : Qt6::Widget
    getter lyrics_panel : Qt6::Widget
    getter queue_panel : Qt6::Widget

    def initialize(
      window : Qt6::MainWindow,
      player_header : PlayerHeaderView,
      database_browser : Qt6::Widget,
      lyrics_view : Qt6::Widget,
      queue_view : QueueView,
    )
      @player_header = player_header
      @central = Qt6::Widget.new(window)

      @browsers = Qt6::Splitter.new(Qt6::Orientation::Horizontal, @central)
      @browsers.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Expanding)

      @database_panel = Qt6::Widget.new(@central)
      @database_panel.minimum_width = 220
      @database_panel.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Expanding)
      @database_panel.vbox do |database_column|
        database_column.spacing = 4
        database_column.set_contents_margins(0, 0, 0, 0)
        database_column << database_browser
      end

      @lyrics_panel = Qt6::Widget.new(@central)
      @lyrics_panel.minimum_width = 220
      @lyrics_panel.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Expanding)
      @lyrics_panel.vbox do |lyrics_column|
        lyrics_column.spacing = 4
        lyrics_column.set_contents_margins(0, 0, 0, 0)
        lyrics_column << lyrics_view
      end

      @queue_panel = Qt6::Widget.new(@central)
      @queue_panel.minimum_width = 220
      @queue_panel.tool_tip = "Drop songs, albums, or artists here to insert them into the queue"
      @queue_panel.set_size_policy(Qt6::SizePolicy::Expanding, Qt6::SizePolicy::Expanding)
      @queue_panel.vbox do |queue_column|
        queue_column.spacing = 4
        queue_column.set_contents_margins(0, 0, 0, 0)
        queue_column << queue_view.view
      end

      @browsers << @database_panel
      @browsers << @lyrics_panel
      @browsers << @queue_panel

      @compact_spacer = Qt6::Widget.new(@central)
      @compact_spacer.set_size_policy(Qt6::SizePolicy::Preferred, Qt6::SizePolicy::Expanding)
      @compact_spacer.visible = false

      @central.vbox do |column|
        column.spacing = 0
        column.set_contents_margins(0, 0, 0, 0)
        column << player_header.root
        column << @browsers
        column << @compact_spacer
      end
    end
  end
end
