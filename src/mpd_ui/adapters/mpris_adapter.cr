module MPDUI
  class MprisAdapter
    getter service : MPRIS::Service
    getter song : Song?
    getter art_url : String = ""
    property cover_path : String?

    @last_position_second : Int64?

    def initialize(
      app_id : String,
      identity : String,
      desktop_entry : String = app_id,
      cache_prefix : String = app_id,
      on_raise : Proc(Nil)? = nil,
      on_quit : Proc(Nil)? = nil,
      on_play : Proc(Nil)? = nil,
      on_pause : Proc(Nil)? = nil,
      on_play_pause : Proc(Nil)? = nil,
      on_stop : Proc(Nil)? = nil,
      on_next : Proc(Nil)? = nil,
      on_previous : Proc(Nil)? = nil,
      on_seek : Proc(Int64, Nil)? = nil,
      on_set_position : Proc(String, Int64, Nil)? = nil,
      on_set_volume : Proc(Float64, Nil)? = nil,
      on_set_shuffle : Proc(Bool, Nil)? = nil,
      on_set_loop_status : Proc(String, Nil)? = nil
    )
      @service = MPRIS::Service.new(
        app_id: app_id,
        identity: identity,
        desktop_entry: desktop_entry,
        cache_prefix: cache_prefix
      )
      @service.on_raise = on_raise
      @service.on_quit = on_quit
      @service.on_play = on_play
      @service.on_pause = on_pause
      @service.on_play_pause = on_play_pause
      @service.on_stop = on_stop
      @service.on_next = on_next
      @service.on_previous = on_previous
      @service.on_seek = on_seek
      @service.on_set_position = on_set_position
      @service.on_set_volume = on_set_volume
      @service.on_set_shuffle = on_set_shuffle
      @service.on_set_loop_status = on_set_loop_status
    end

    def start : Nil
      @service.start
    end

    def stop : Nil
      @service.stop
    end

    def cache_prefix : String
      @service.options.cache_prefix
    end

    def art_url=(value : String) : String
      @art_url = value
    end

    def sync_position(playback : PlaybackState) : Nil
      second = playback.elapsed.floor.to_i64
      return if @last_position_second == second

      @last_position_second = second
      sync(playback)
    end

    def sync(playback : PlaybackState, song : Song? = nil) : Nil
      @song = song if song
      song ||= @song

      state = MPRIS::State.new
      state.playback_status =
        if playback.playing?
          "Playing"
        elsif playback.paused?
          "Paused"
        else
          "Stopped"
        end

      state.position_us = (playback.elapsed * 1_000_000).round.to_i64
      @last_position_second = playback.elapsed.floor.to_i64
      state.length_us = (playback.duration * 1_000_000).round.to_i64
      state.volume = playback.volume ? (playback.volume.not_nil!.clamp(0, 100) / 100.0) : 1.0
      state.shuffle = playback.random
      state.repeat = playback.repeat

      if song
        state.file = song.file || ""
        state.title = song.display_title
        state.artist = song.artist || ""
        state.album = song.album || ""
        state.art_url = @art_url
        state.track_id = song.id
      end

      @service.update_state(state)
    end
  end
end
