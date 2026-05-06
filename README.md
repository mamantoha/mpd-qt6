# Crystal MPD

A desktop [MPD](https://www.musicpd.org/) client written in [Crystal](https://crystal-lang.org/) using [Qt6](https://github.com/djberg96/crystal-qt6) shard.

## Screenshots

![Player](screenshot.png)

## Features

- Playback controls for play, pause, previous, and next
- Interactive progress slider with elapsed and total time display
- Progress tooltip while hovering or dragging the progress slider
- Playback controls and progress slider disable cleanly when playback is stopped
- Shuffle and repeat toggles
- Volume button with a dropdown vertical slider and percentage display
- Live track, artist, and album metadata updates
- Window title updates to reflect the current song
- Album art loading from MPD when available, including a full-size cover tooltip
- Click the album art to toggle the expanded interface
- Optional blurred album-art playback header background
- Queue view with current-track state icons, multi-select, auto-scroll, and current-song selection sync
- Double-click or press Enter on a queue row to start playback instantly
- Queue reordering with drag and drop
- Remove selected queue rows with Delete
- Queue context menu for playing the selected song now or removing selected songs
- Clear queue action from the main menu and keyboard shortcut
- Database browser grouped as artist → album → songs with item icons and two-line rows
- Database browser album sorting by year and song sorting by disc and track number
- Database search/filter by artist, album, title, and file path with `Ctrl+F` and `Esc` to close
- Reload Database updates MPD's database before refreshing the local browser
- Multi-select artists, albums, or songs in the database browser
- Library context menu for adding the selected artist, album, or song selection to the queue
- Song information tooltips in both the queue and database browser
- Toggleable expanded interface and library panel
- Drag and drop selected songs, albums, or artists from the database into the queue
- Drop-position queue insertion for fast playlist building
- Main menu with About, Settings, Library, and Queue actions
- Top-right Options menu reusing main-menu actions
- Toggleable main menu bar with persisted visibility and `Ctrl+M` shortcut
- About dialog with application details and live MPD server statistics
- Connection settings dialog for MPD host and port
- System tray integration with tray menu, close-to-tray behavior, restore/show toggle, and playback actions
- MPRISv2 integration for Linux desktop media controls, metadata, position, volume, shuffle/repeat state, and cover art
- Optional Last.fm scrobbling with one-time authentication, now-playing updates, threshold-based scrobbles, and retry cache for failed scrobbles
- Settings persisted in the user config directory, including connection details, Last.fm session details, UI visibility, blurred cover background, expanded window size, and library/queue splitter sizes

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
shards build --release -Dpreview_mt
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

- `src/mpd_ui/app.cr` owns the main `App` class and acts mostly as the composition root: it loads settings, creates the Qt application/window, wires views/controllers/adapters together, starts MPD, and runs the Qt event loop
- Domain/service objects keep non-Qt behavior isolated:
  - `song.cr` and `playback_state.cr` wrap MPD song metadata and current playback state
  - `cover_art_service.cr` fetches MPD cover art and handles the disk cover cache
  - `library_index.cr` handles database filtering, artist/album/song grouping, album sorting by year, and song sorting by disc/track
  - `background_task.cr` centralizes short worker-thread jobs and Qt-main-thread callbacks
- View classes under `src/mpd_ui/views/` own Qt widget construction and rendering:
  - `application_menu.cr` builds the main menu/actions and menu shortcuts
  - `app_layout_view.cr` arranges the player header, library/queue splitter, and compact spacer
  - `player_header_view.cr` owns the playback header widgets, controls, volume popup, cover click handling, and progress tooltip
  - `queue_view.cr` owns the queue `QTreeView`, model rendering, context menu, shortcuts, selection helpers, drop filter, and row indicators
  - `library_view.cr` owns the database browser tree, search panel, custom item delegate, context menu, drag filter, and selected URI collection
- Controller classes under `src/mpd_ui/controllers/` keep state transitions and queue calculations away from Qt widget setup:
  - `player_controller.cr` reads MPD status/current-song/playlist snapshots and converts them into `PlaybackState` transitions
  - `queue_controller.cr` tracks queue positions/ids and plans multi-row reorders
- App glue modules under `src/mpd_ui/app/` connect views/controllers/services to MPD commands and UI state:
  - `player.cr` handles playback refresh, progress, volume, cover rendering, blurred header background, and current-song UI updates
  - `queue.cr` wires `QueueView`/`QueueController` to MPD queue commands and database-to-queue drops
  - `database.cr` wires `LibraryView`/`LibraryIndex` to MPD database loading, searching, and add-to-queue behavior
  - `mpris.cr` connects Qt/MPD callbacks to the app-specific MPRIS adapter
  - `lastfm.cr` feeds playback snapshots into the app-specific Last.fm adapter
  - `tray.cr` handles system tray integration, close-to-tray behavior, and tray menu actions
  - `about_dialog.cr` and `settings_dialog.cr` keep dialogs isolated from the main UI setup
- `src/mpd_ui/adapters/` contains app-specific integration adapters:
  - `mpris_adapter.cr` owns `MPRIS::Service`, callback registration, playback-state mapping, current MPRIS song/artwork state, and position sync throttling
  - `lastfm_adapter.cr` owns Last.fm client/scrobbler construction and playback sync
- `src/ext/mpris` contains a small Crystal MPRIS/DBus implementation kept separate from Qt-specific app code
- `src/ext/lastfm` contains the Last.fm API client, request signing, scrobble timing, and retry cache
- One MPD client handles commands and status reads
- A separate callback-enabled MPD listener pushes live updates from the server
- `EventBridge` marshals callback-thread updates safely onto the Qt main thread
- `Settings` wraps `QSettings` persistence for connection details, UI visibility preferences, layout size, and splitter state
- The UI uses Qt Widgets directly, including `QMainWindow`, menus/actions, push buttons, sliders, splitters, tree views, standard item models, custom item delegates, event filters, shortcuts, and graphics effects

## License

MIT
