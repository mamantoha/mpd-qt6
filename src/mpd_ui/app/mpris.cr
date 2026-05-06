module MPDUI
  module AppMPRIS
    private def setup_mpris : Nil
      adapter = MprisAdapter.new(
        app_id: Settings::APPLICATION,
        identity: App::WINDOW_TITLE,
        desktop_entry: Settings::APPLICATION,
        cache_prefix: Settings::APPLICATION,
        on_raise: -> { @qt_app.invoke_later { show_main_window } },
        on_quit: -> { @qt_app.invoke_later { quit_application } },
        on_play: -> { @qt_app.invoke_later { mpd_action(&.play) } },
        on_pause: -> { @qt_app.invoke_later { mpd_action(&.pause(true)) } },
        on_play_pause: -> { @qt_app.invoke_later { toggle_play_pause } },
        on_stop: -> { @qt_app.invoke_later { mpd_action(&.stop) } },
        on_next: -> { @qt_app.invoke_later { mpd_action(&.next) } },
        on_previous: -> { @qt_app.invoke_later { mpd_action(&.previous) } },
        on_seek: ->(offset_us : Int64) { handle_mpris_seek(offset_us) },
        on_set_position: ->(_track_id : String, position_us : Int64) { handle_mpris_set_position(position_us) },
        on_set_volume: ->(volume : Float64) { handle_mpris_set_volume(volume) },
        on_set_shuffle: ->(enabled : Bool) { @qt_app.invoke_later { mpd_action(&.random(enabled)) } },
        on_set_loop_status: ->(status : String) { handle_mpris_set_loop_status(status) }
      )

      @mpris_adapter = adapter
      adapter.start
      sync_mpris_state(nil)
    end

    private def handle_mpris_seek(offset_us : Int64) : Nil
      @qt_app.invoke_later do
        seconds = offset_us / 1_000_000
        next if seconds == 0

        value = seconds > 0 ? "+#{seconds}" : seconds.to_s
        mpd_action(&.seekcur(value))
      end
    end

    private def handle_mpris_set_position(position_us : Int64) : Nil
      @qt_app.invoke_later do
        seconds = (position_us / 1_000_000).clamp(0_i64, Int32::MAX.to_i64)
        mpd_action(&.seekcur(seconds.to_i))
      end
    end

    private def handle_mpris_set_volume(volume : Float64) : Nil
      @qt_app.invoke_later do
        percent = (volume.clamp(0.0, 1.0) * 100).round.to_i
        mpd_action(&.setvol(percent))
      end
    end

    private def handle_mpris_set_loop_status(status : String) : Nil
      @qt_app.invoke_later do
        next unless status == "Playlist" || status == "Track" || status == "None"

        enabled =
          case status
          when "Track"
            !@playback_state.repeat
          when "Playlist"
            true
          else
            false
          end

        mpd_action(&.repeat(enabled))
      end
    end

    private def sync_mpris_position : Nil
      @mpris_adapter.try(&.sync_position(@playback_state))
    end

    private def sync_mpris_state(song : Song? = nil) : Nil
      @mpris_adapter.try(&.sync(@playback_state, song))
    end
  end
end
