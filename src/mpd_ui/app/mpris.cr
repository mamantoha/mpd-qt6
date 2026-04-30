module MPDUI
  module AppMPRIS
    private def setup_mpris : Nil
      service = MPRIS::Service.new(MPRIS::Options.new(
        app_id: Settings::APPLICATION,
        identity: App::WINDOW_TITLE,
        desktop_entry: Settings::APPLICATION,
        cache_prefix: Settings::APPLICATION
      ))
      service.on_raise = ->{ @qt_app.invoke_later { show_main_window } }
      service.on_quit = ->{ @qt_app.invoke_later { quit_application } }
      service.on_play = ->{ @qt_app.invoke_later { mpd_action { |client| client.play } } }
      service.on_pause = ->{ @qt_app.invoke_later { mpd_action { |client| client.pause(true) } } }
      service.on_play_pause = ->{ @qt_app.invoke_later { toggle_play_pause } }
      service.on_stop = ->{ @qt_app.invoke_later { mpd_action { |client| client.stop } } }
      service.on_next = ->{ @qt_app.invoke_later { mpd_action { |client| client.next } } }
      service.on_previous = ->{ @qt_app.invoke_later { mpd_action { |client| client.previous } } }
      service.on_seek = ->(offset_us : Int64) do
        @qt_app.invoke_later do
          seconds = offset_us / 1_000_000
          next if seconds == 0

          value = seconds > 0 ? "+#{seconds}" : seconds.to_s
          mpd_action { |client| client.seekcur(value) }
        end
      end
      service.on_set_position = ->(_track_id : String, position_us : Int64) do
        @qt_app.invoke_later do
          seconds = (position_us / 1_000_000).clamp(0_i64, Int32::MAX.to_i64)
          mpd_action { |client| client.seekcur(seconds.to_i) }
        end
      end
      service.on_set_volume = ->(volume : Float64) do
        @qt_app.invoke_later do
          percent = (volume.clamp(0.0, 1.0) * 100).round.to_i
          @volume = percent
          update_volume_icon(percent)
          update_volume_label(percent)
          sync_mpris_state
          mpd_action { |client| client.setvol(percent) }
        end
      end
      service.on_set_shuffle = ->(enabled : Bool) do
        @qt_app.invoke_later do
          @random = enabled
          sync_toggle_buttons
          sync_mpris_state
          mpd_action { |client| client.random(enabled) }
        end
      end
      service.on_set_loop_status = ->(status : String) do
        @qt_app.invoke_later do
          next unless status == "Playlist" || status == "Track" || status == "None"

          enabled = case status
                    when "Track"
                      !@repeat
                    when "Playlist"
                      true
                    else
                      false
                    end
          @repeat = enabled
          sync_toggle_buttons
          sync_mpris_state
          mpd_action { |client| client.repeat(enabled) }
        end
      end

      @mpris_service = service
      service.start
      sync_mpris_state(nil)
    end

    private def sync_mpris_state(song : Hash(String, String)? = nil) : Nil
      service = @mpris_service
      return unless service

      @mpris_song = song if song
      song ||= @mpris_song

      state = MPRIS::State.new
      state.playback_status = case @state
                              when "play"
                                "Playing"
                              when "pause"
                                "Paused"
                              else
                                "Stopped"
                              end
      state.position_us = (@elapsed * 1_000_000).round.to_i64
      state.length_us = (@duration * 1_000_000).round.to_i64
      state.volume = @volume ? (@volume.not_nil!.clamp(0, 100) / 100.0) : 1.0
      state.shuffle = @random
      state.repeat = @repeat

      if song
        file = song["file"]?
        state.file = file || ""
        state.title = song["Title"]? || (file ? File.basename(file, File.extname(file)) : "")
        state.artist = song["Artist"]? || ""
        state.album = song["Album"]? || ""
        state.art_url = @mpris_art_url
        state.track_id = song["Id"]?.try(&.to_i?)
      end

      service.update_state(state)
    end
  end
end
