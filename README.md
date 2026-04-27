# Crystal MPD

A desktop [MPD](https://www.musicpd.org/) client written in [Crystal](https://crystal-lang.org/) using [Qt6](https://github.com/djberg96/crystal-qt6) shard.

## Screenshots

![Player](screenshot.png)

## Features

- Playback controls for play, pause, previous, and next
- Interactive progress slider with elapsed and total time display
- Shuffle and repeat toggles
- Volume button with a dropdown vertical slider and percentage display
- Live track, artist, and album metadata updates
- Window title updates to reflect the current song
- Album art loading from MPD when available
- Queue view with current-track state icons, multi-select, auto-scroll, and current-song selection sync
- Double-click a queue row to start playback instantly
- Queue reordering with drag and drop
- Remove selected queue rows with Delete
- Clear queue action from the main menu and keyboard shortcut
- Database browser grouped as artist → album → songs with item icons
- Multi-select artists, albums, or songs in the database browser
- Toggleable expanded interface and library panel
- Drag and drop selected songs, albums, or artists from the database into the queue
- Drop-position queue insertion for fast playlist building
- Main menu with About, Settings, Library, and Queue actions
- Top-right Options menu with Settings, Reload Database, Expanded Interface, Show Main Menu, and About actions
- Toggleable main menu bar with persisted visibility and `Ctrl+M` shortcut
- About dialog with application details and live MPD server statistics
- Connection settings dialog for MPD host and port
- System tray integration with tray menu, close-to-tray behavior, restore/show toggle, and playback actions
- Settings persisted in the user config directory, including host, port, expanded interface, library visibility, and main menu visibility

## Requirements

- Crystal >= 1.19.1
- Qt6 Widgets development packages
  - Arch: `pacman -S qt6-base`
  - Ubuntu: `apt-get install qt6-base-dev`
  - macOS: `brew install qt`
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

Tested on Linux and macOS with Qt6. Windows are untested.

## Architecture notes

- `src/mpd_ui/app.cr` owns the main `App` class, shared UI state, top-level layout, menus, and persisted visibility controls
- Feature modules under `src/mpd_ui/app/` split the app by responsibility:
  - `player.cr` handles playback state, progress, volume, cover art, and current-song UI updates
  - `queue.cr` handles the queue table, multi-select deletion, drag/drop reordering, and database-to-queue drops
  - `database.cr` handles the MPD database tree, artist/album/song grouping, tree icons, multi-selection, and database drag sources
  - `tray.cr` handles system tray integration, close-to-tray behavior, and tray menu actions
  - `about_dialog.cr` and `settings_dialog.cr` keep dialogs isolated from the main UI setup
- One MPD client handles commands and status reads
- A separate callback-enabled MPD listener pushes live updates from the server
- `EventBridge` marshals callback-thread updates safely onto the Qt main thread
- `Settings` wraps `QSettings` persistence for connection details and UI visibility preferences
- The UI uses Qt Widgets directly, including `QMainWindow`, menus/actions, push buttons, sliders, splitters, table views, tree views, and standard item models

## License

MIT
