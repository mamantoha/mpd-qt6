# Crystal MPD

A desktop [MPD](https://www.musicpd.org/) client written in [Crystal](https://crystal-lang.org/) using [Qt6](https://github.com/djberg96/crystal-qt6) bindings.

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
| [djberg96/crystal-qt6](https://github.com/djberg96/crystal-qt6) | Qt6 bindings for Crystal |
| [mamantoha/crystal_mpd](https://github.com/mamantoha/crystal_mpd) | MPD protocol client |

## Platform support

Tested on Linux with Qt6. macOS and Windows are untested.

## Architecture notes

- One MPD client handles commands and status reads
- A separate callback-enabled MPD listener pushes live updates from the server
- UI updates are marshalled safely onto the Qt main thread through a signal-style bridge
- Playback and playlist controls are built with Qt widgets such as push buttons, sliders, and table views

## License

MIT
