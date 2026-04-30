# MPRIS

Small Crystal implementation of the MPRISv2 DBus interface for desktop media
player integration.

This code is currently embedded in `mpd-qt6` under `src/ext/mpris` as a
preparation step for extracting it into a separate shard.

## Features

- Registers an MPRIS player on the DBus session bus.
- Exposes `org.mpris.MediaPlayer2`.
- Exposes `org.mpris.MediaPlayer2.Player`.
- Supports desktop media controls:
  - raise
  - quit
  - play
  - pause
  - play/pause
  - stop
  - next
  - previous
  - seek
  - set position
  - set volume
- Publishes player state:
  - playback status
  - metadata
  - position
  - duration
  - volume
  - shuffle
  - repeat
  - cover art URL
- Emits `PropertiesChanged` when player state changes.

## Requirements

- Crystal
- Linux desktop session with DBus
- `DBUS_SESSION_BUS_ADDRESS` available in the environment

No Qt dependency is required by the MPRIS module itself.

## Basic Usage

```crystal
require "mpris"

player = MyPlayerBackend.new

# The service owns the DBus/MPRIS connection. These options decide how desktop
# clients discover and display your player.
service = MPRIS::Service.new(
  MPRIS::Options.new(
    app_id: "my-player",
    identity: "My Player",
    desktop_entry: "my-player"
  )
)

# Desktop -> player:
# MPRIS calls these callbacks when media keys, desktop controls, or playerctl
# request an action. Your app should forward each callback to its real backend.
service.on_play = ->{ player.play }
service.on_pause = ->{ player.pause }
service.on_play_pause = ->{ player.toggle_play_pause }
service.on_stop = ->{ player.stop }
service.on_next = ->{ player.next }
service.on_previous = ->{ player.previous }
service.on_seek = ->(offset_us : Int64) { player.seek_relative(offset_us) }
service.on_set_position = ->(track_id : String, position_us : Int64) {
  player.seek_to(track_id, position_us)
}
service.on_set_volume = ->(volume : Float64) { player.volume = volume }
service.on_set_shuffle = ->(enabled : Bool) { player.shuffle = enabled }
service.on_set_loop_status = ->(status : String) {
  player.repeat = status != "None"
}

# Start listening on the DBus session bus and claim the MPRIS player name.
service.start

# Player -> desktop:
# Build a snapshot from your real player state whenever playback state,
# metadata, position, volume, or cover art changes.
state = MPRIS::State.new
state.playback_status = "Playing"
state.title = "Song Title"
state.artist = "Artist"
state.album = "Album"
state.length_us = 180_000_000_i64
state.position_us = 42_000_000_i64
state.volume = 0.75
state.art_url = "file:///tmp/cover.jpg"

# Publish the snapshot and notify desktop clients with PropertiesChanged.
service.update_state(state)
```

## Data Flow

MPRIS is a bridge between your player and the desktop session.

There are two directions:

```text
your player/backend -> MPRIS -> desktop shell, media keys UI, playerctl
desktop shell/playerctl -> MPRIS -> your player/backend
```

### Player To Desktop

Your application owns playback state. When the current song, playback status,
position, volume, or artwork changes, build a new `MPRIS::State` and pass it to
the service:

```crystal
state = MPRIS::State.new
state.playback_status = "Playing"
state.title = current_song.title
state.artist = current_song.artist
state.position_us = current_position_us
state.length_us = current_duration_us
state.volume = current_volume_percent / 100.0
state.art_url = current_cover_art_url

service.update_state(state)
```

`update_state` stores the latest snapshot and emits DBus `PropertiesChanged`.
Desktop clients then refresh their UI by reading MPRIS properties such as
`PlaybackStatus`, `Metadata`, `Position`, and `Volume`.

### Desktop To Player

Desktop controls do not play audio themselves. They call MPRIS methods, and this
service forwards those requests to your callbacks.

For example:

```text
playerctl play-pause
  -> org.mpris.MediaPlayer2.Player.PlayPause()
  -> service.on_play_pause
  -> your player toggles playback
```

You connect callbacks to your backend:

```crystal
service.on_play_pause = ->{ player.toggle_play_pause }
service.on_next = ->{ player.next }
service.on_previous = ->{ player.previous }
service.on_seek = ->(offset_us : Int64) {
  player.seek_relative(offset_us)
}
service.on_set_volume = ->(volume : Float64) {
  player.volume = (volume * 100).round.to_i
}
service.on_set_shuffle = ->(enabled : Bool) {
  player.shuffle = enabled
}
service.on_set_loop_status = ->(status : String) {
  player.repeat = status != "None"
}
```

After your backend changes state, call `update_state` again so desktop clients
see the result of the command.

## Options

`MPRIS::Options` configures how the player is published:

- `app_id`: used to build the DBus bus name
  `org.mpris.MediaPlayer2.<app_id>`.
- `identity`: human-readable player name shown by desktop shells.
- `desktop_entry`: desktop entry id, usually the `.desktop` filename without
  `.desktop`.
- `cache_prefix`: optional helper prefix used by embedding applications for
  temporary cover-art files.

`app_id` is sanitized for DBus by replacing unsupported characters with `_`.

## State

`MPRIS::State` is the snapshot exposed to desktop clients.

Common fields:

- `playback_status`: `"Playing"`, `"Paused"`, or `"Stopped"`.
- `title`
- `artist`
- `album`
- `file`
- `art_url`
- `track_id`
- `length_us`
- `position_us`
- `volume`: `0.0..1.0`
- `shuffle`
- `repeat`

Call `service.update_state(state)` whenever the player state or metadata
changes.

## Current Limitations

- Supports only Unix session bus addresses with `unix:path=...`.
- Implements only the DBus types needed for MPRIS.
- Does not implement `OpenUri`.
- Does not implement MPRIS track lists.
- Shutdown is intentionally lightweight: `stop` marks the service as stopped.

## Testing

While a player using this service is running:

```sh
playerctl -l
playerctl -p mpd_qt6 metadata
playerctl -p mpd_qt6 play-pause
playerctl -p mpd_qt6 next
playerctl -p mpd_qt6 previous
```

To inspect the published artwork:

```sh
playerctl metadata mpris:artUrl
```
