module MPDUI
  class PlaylistTreeSelection
    ROW_TYPE_SONG = PlaylistsModel::ROW_TYPE_SONG

    property last_selected_playlist_name : String?

    @selected_song_uris_cache : Array(String) = [] of String
    @selected_song_positions_cache : Array(Int32) = [] of Int32
    @selected_song_playlist_name_cache : String?
    @selection_cache_dirty = true

    def initialize(@view : Qt6::TreeView, @model : PlaylistsModel)
    end

    def selected_playlist_name : String?
      index = @view.current_index
      begin
        return playlist_name_for_index(index) if index.valid?
      ensure
        index.release
      end

      @last_selected_playlist_name
    end

    def selected_song_uris : Array(String)
      refresh_if_dirty
      @selected_song_uris_cache.dup
    end

    def selected_song_positions : Array(Int32)
      refresh_if_dirty
      @selected_song_positions_cache.dup
    end

    def selected_song? : Bool
      refresh_if_dirty
      !@selected_song_positions_cache.empty?
    end

    def current_song? : Bool
      index = @view.current_index
      begin
        song_index?(index)
      ensure
        index.release
      end
    end

    def song_index_at?(position : Qt6::PointF) : Bool
      index = @view.index_at(position)
      begin
        song_index?(index)
      ensure
        index.release
      end
    end

    def song_index?(index : Qt6::ModelIndex) : Bool
      row_type(index) == ROW_TYPE_SONG
    end

    def playlist_name_for_index(index : Qt6::ModelIndex) : String?
      return unless index.valid?

      index.data(@model, ItemRoles::PLAYLIST_NAME).as?(String)
    end

    def song_uri_for_index(index : Qt6::ModelIndex) : String?
      return unless song_index?(index)

      uri = index.data(@model, ItemRoles::PLAYLIST_SONG_URI).as?(String)
      uri unless uri.nil? || uri.empty?
    end

    def song_position_for_index(index : Qt6::ModelIndex) : Int32?
      return unless song_index?(index)

      index.data(@model, ItemRoles::PLAYLIST_SONG_POSITION).as?(Int32)
    end

    def select_index_if_needed(index : Qt6::ModelIndex) : Nil
      selection_model = @view.selection_model
      unless selection_model && selection_model.selected?(index)
        selection_model.try(&.set_current_index(index, Qt6::SelectionFlag::ClearAndSelect | Qt6::SelectionFlag::Rows))
        @view.current_index = index
      end
    end

    def select_playlist(name : String?) : Nil
      return unless name

      index = @model.index_for_playlist(name)
      return unless index

      begin
        @view.selection_model.try(&.set_current_index(index, Qt6::SelectionFlag::ClearAndSelect | Qt6::SelectionFlag::Rows))
        @view.current_index = index
      ensure
        index.release
      end
    end

    def mark_dirty : Nil
      @selection_cache_dirty = true
    end

    def refresh_if_dirty : Nil
      refresh if @selection_cache_dirty
    end

    def drag_snapshot(index : Qt6::ModelIndex, playlist_name : String, song_position : Int32, song_uri : String) : Tuple(String, Array(Int32), Array(String))
      selection_model = @view.selection_model
      selected_drag = selection_model && selection_model.selected?(index)
      refresh_if_dirty if selected_drag

      if selected_drag && @selected_song_playlist_name_cache == playlist_name && @selected_song_positions_cache.includes?(song_position)
        {playlist_name, @selected_song_positions_cache.dup, @selected_song_uris_cache.dup}
      else
        @selected_song_playlist_name_cache = playlist_name
        @selected_song_positions_cache = [song_position]
        @selected_song_uris_cache = [song_uri]
        @selection_cache_dirty = false
        {playlist_name, @selected_song_positions_cache.dup, @selected_song_uris_cache.dup}
      end
    end

    private def selected_song_indexes : Array(Qt6::ModelIndex)
      selection_model = @view.selection_model
      return [] of Qt6::ModelIndex unless selection_model

      selection_model.selected_rows(0).compact_map do |index|
        if index.valid? && song_index?(index)
          index
        else
          index.release
          nil
        end
      end
    end

    private def current_song_indexes : Array(Qt6::ModelIndex)
      index = @view.current_index
      unless index.valid? && song_index?(index)
        index.release
        return [] of Qt6::ModelIndex
      end

      [index]
    end

    private def refresh : Nil
      uris = [] of String
      positions = [] of Int32
      playlist_name : String? = nil

      indexes = selected_song_indexes
      begin
        indexes.each do |index|
          index_playlist_name = playlist_name_for_index(index)
          uri = song_uri_for_index(index)
          position = song_position_for_index(index)
          next unless index_playlist_name && uri && position

          playlist_name ||= index_playlist_name
          next unless playlist_name == index_playlist_name

          uris << uri
          positions << position
        end
      ensure
        indexes.each(&.release)
      end

      if uris.empty?
        indexes = current_song_indexes
        begin
          indexes.each do |index|
            index_playlist_name = playlist_name_for_index(index)
            uri = song_uri_for_index(index)
            position = song_position_for_index(index)
            next unless index_playlist_name && uri && position

            playlist_name = index_playlist_name
            uris << uri
            positions << position
          end
        ensure
          indexes.each(&.release)
        end
      end

      @selected_song_playlist_name_cache = playlist_name
      @selected_song_uris_cache = uris.uniq!
      @selected_song_positions_cache = positions
      @selection_cache_dirty = false
    end

    private def row_type(index : Qt6::ModelIndex) : String?
      return unless index.valid?

      index.data(@model, ItemRoles::PLAYLIST_ROW_TYPE).as?(String)
    end
  end
end
