module MPDUI
  class DragContext
    enum Source
      Queue
      Database
      StoredPlaylist
    end

    getter source : Source?
    property queue_source_row : Int32?

    def begin_queue_drag(row : Int32?) : Nil
      @source = Source::Queue
      @queue_source_row = row
    end

    def begin_database_drag : Nil
      @source = Source::Database
      @queue_source_row = nil
    end

    def begin_stored_playlist_drag : Nil
      @source = Source::StoredPlaylist
      @queue_source_row = nil
    end

    def assume_queue_drag : Nil
      @source ||= Source::Queue
    end

    def reset_selection : Nil
      @queue_source_row = nil
    end

    def finish_drag : Nil
      @source = nil
      @queue_source_row = nil
    end

    def queue? : Bool
      @source == Source::Queue
    end

    def database? : Bool
      @source == Source::Database
    end

    def stored_playlist? : Bool
      @source == Source::StoredPlaylist
    end

    def external_uri_source? : Bool
      database? || stored_playlist?
    end
  end
end
