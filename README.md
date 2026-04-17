# Crystal MPD

A desktop [MPD](https://www.musicpd.org/) client written in [Crystal](https://crystal-lang.org/) using a forked [Qt6](https://github.com/mamantoha/crystal-qt6) shard.

## Screenshots

![Player](screenshot.png)

## Features

- Playback controls: play/pause, previous, next
- Interactive progress slider with elapsed and total time display
- Shuffle and repeat toggles
- Live title, artist, and album metadata updates
- Window title updates to reflect the current track
- Album art loading when available from MPD
- Playlist view with current-track indicator icons
- Double-click a playlist row to start playback
- Connection settings dialog for MPD host and port
- Settings are saved in the user config directory

## Requirements

- Crystal >= 1.19.1
- Qt6 Widgets development packages
  - Arch: `pacman -S qt6-base`
  - Ubuntu: `apt-get install qt6-base-dev`
- A running MPD server

## Installation

```sh
git clone https://github.com/mamantoha/mpd-qt6
cd mpd-qt6
shards install
shards build --release
./bin/mpd-qt6
```

## Dependencies

| Shard | Purpose |
|---|---|
| [mamantoha/crystal-qt6](https://github.com/mamantoha/crystal-qt6) | Forked Qt6 bindings for Crystal used by this app |
| [mamantoha/crystal_mpd](https://github.com/mamantoha/crystal_mpd) | MPD protocol client |

## Forked Qt6 shard

This project currently uses a forked version of crystal-qt6 through a local path dependency during development.

### Features implemented in the fork

The local Qt6 fork includes several additions that are used by this application:

- main-thread invocation support via Qt meta-object dispatch
- loading icons from the active desktop theme
- slider pressed and released callbacks
- label pixmap support and alignment helpers
- pixmap scaling with aspect-ratio preservation
- table widget item double-click callbacks
- table widget item icon support
- native add_stretch support for box layouts
- improved model and item-view drag-and-drop configuration
- item-view viewport access for native drop handling
- hit-testing helpers to resolve the row under the cursor
- visual-rectangle queries for accurate native drop indicator placement

These additions are what make the queue and database browser integration possible without falling back to a fully custom drag-and-drop overlay.

## Platform support

Tested on Linux with Qt6. macOS and Windows are untested.

## Architecture notes

- One MPD client handles commands and status reads
- A separate callback-enabled MPD listener pushes live updates from the server
- UI updates are marshalled safely onto the Qt main thread through a signal-style bridge
- Playback and playlist controls are built with Qt widgets such as push buttons, sliders, and table views

## License

MIT
