# Crystal MPD

A desktop [MPD](https://www.musicpd.org/) client written in [Crystal](https://crystal-lang.org/) using [Qt6](https://github.com/djberg96/crystal-qt6) bindings.

## Screenshots

![Player](screenshot.png)

## Features

- Playback controls: play/pause, previous, next
- Shuffle and repeat toggles
- Live track title and subtitle display
- Window title updates to reflect the current track
- Simple Qt6 foundation for the upcoming playlist and cover art UI

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

- A single `MPD::Client` handles commands and periodic status refresh
- A `Qt6::QTimer` polls MPD once per second to keep the UI in sync
- Playback controls are implemented with `Qt6::PushButton` and `Qt6::CheckBox`

## License

MIT
