# Garnetune

A desktop [MPD](https://www.musicpd.org/) client written in [Crystal](https://crystal-lang.org/) using [Qt6](https://github.com/djberg96/crystal-qt6) shard.

## Screenshots

![Player](screenshot.png)

## Features

- Playback controls with progress seeking, shuffle/repeat, volume control, and current song metadata.
- Album art support, including a full-size cover preview and optional blurred cover background in the playback header.
- Queue management with multi-select, drag-and-drop reordering, keyboard playback, row removal, and context menu actions.
- Library browser grouped by artist, album, and song, with natural album/year and disc/track sorting.
- Library search by artist, album, title, and file path, plus genre filtering from MPD's database tags.
- Drag artists, albums, songs, or stored playlist tracks into the queue, including insertion at the drop position.
- Saved playlist management: browse MPD playlists, preview songs, save the current queue, rename/delete playlists, append playlists to the queue, or replace the queue with a playlist.
- Configurable MPD connection and optional Last.fm scrobbling.
- MPD output management for enabling or disabling configured audio outputs.
- Optional MPD FIFO spectrum visualizer in the playback header.
- Linux desktop integration through MPRISv2 for media keys, desktop media widgets, metadata, position, volume, shuffle/repeat, and cover art.
- System tray support with close-to-tray behavior, restore/show toggle, and playback actions.
- Persistent UI preferences for layout, expanded mode, menu visibility, blurred cover background, visualizer settings, window size, and splitter sizes.

## Requirements

- Crystal >= 1.19.1
- Garnetune must be built with Crystal's multithreaded execution context flags:
  `-Dpreview_mt -Dexecution_context`
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
shards build --release -Dpreview_mt -Dexecution_context
./bin/garnetune
```

For local development, use the same flags:

```sh
crystal run src/main.cr -Dpreview_mt -Dexecution_context
```

## Visualizer

Garnetune can show a spectrum visualizer in the playback header. MPD must be
configured to write raw PCM audio to a FIFO because MPD does not expose spectrum
data directly.

Add a FIFO output to `mpd.conf`:

```conf
audio_output {
    type   "fifo"
    name   "visualizer"
    path   "/tmp/mpd.fifo"
    format "44100:16:2"
}
```

Restart MPD after changing the config. In Garnetune, open Settings ->
Visualizer, enable the visualizer, and set the FIFO path to the same value,
for example `/tmp/mpd.fifo`.

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
  - `visualizer_service.cr` reads MPD's raw FIFO audio, tracks FIFO availability/playback state, and exposes normalized levels for the UI
  - `library_index.cr` handles database filtering, artist/album/song grouping, album sorting by year, and song sorting by disc/track
  - `background_task.cr` centralizes short worker-thread jobs and Qt-main-thread callbacks
- `src/mpd_ui/dsp/` contains small audio-processing helpers:
  - `spectrum_analyzer.cr` converts raw PCM frames into logarithmic FFT spectrum bands for the header visualizer
- View classes under `src/mpd_ui/views/` own Qt widget construction and rendering:
  - `application_menu.cr` builds the main menu/actions and menu shortcuts
  - `app_layout_view.cr` arranges the player header, library/queue splitter, and compact spacer
  - `player_header_view.cr` owns the playback header widgets, visualizer widget, controls, volume popup, cover click handling, and progress tooltip
  - `visualizer_widget.cr` paints spectrum bars from `VisualizerService`
  - `queue_view.cr` owns the queue `QTreeView`, context menu, shortcuts, selection helpers, drop filter, and row indicators
  - `library_view.cr` owns the database browser tree, search panel, genre filter, custom item delegate, context menu, drag filter, and selected URI collection
  - `playlists_view.cr` owns the saved playlist tree, playlist/song context menus, and playlist-song drag source
- Custom Qt models under `src/mpd_ui/models/` adapt domain data to Qt's model/view API:
  - `queue_model.cr` exposes the current MPD queue as a flat `QAbstractItemModel` with drag/drop payloads and row indicator updates
  - `library_model.cr` exposes the artist/album/song database tree without building thousands of `QStandardItem` objects
  - `playlists_model.cr` exposes stored playlists and their songs as a tree model with playlist/song roles for context menus and drag/drop
  - These models keep data in Crystal objects and let Qt query rows, parents, roles, tooltips, and MIME data on demand
- Controller classes under `src/mpd_ui/controllers/` keep state transitions and queue calculations away from Qt widget setup:
  - `player_controller.cr` reads MPD status/current-song/playlist snapshots and converts them into `PlaybackState` transitions
  - `queue_controller.cr` tracks queue positions/ids and plans multi-row reorders
- App glue modules under `src/mpd_ui/app/` connect views/controllers/services to MPD commands and UI state:
  - `player.cr` handles playback refresh, progress, volume, cover rendering, blurred header background, visualizer playback state, and current-song UI updates
  - `queue.cr` wires `QueueView`/`QueueController` to MPD queue commands and database-to-queue drops
  - `database.cr` wires `LibraryView`/`LibraryIndex` to MPD database loading, searching, genre filtering, and add-to-queue behavior
  - `playlists.cr` wires `PlaylistsView` to MPD saved playlist commands
  - `mpris.cr` connects Qt/MPD callbacks to the app-specific MPRIS adapter
  - `lastfm.cr` feeds playback snapshots into the app-specific Last.fm adapter
  - `outputs.cr` loads MPD audio outputs and applies output enable/disable commands from the UI
  - `window_events.cr` handles main-window close/show/hide/resize policy, including close-to-tray when a tray icon exists and expanded-window size tracking
  - `tray.cr` handles only system tray integration: tray icon/menu setup, tray activation, tray messages, tray state, and tray tooltip updates
  - `about_dialog.cr` and `settings_dialog.cr` keep dialogs isolated from the main UI setup
- `src/mpd_ui/adapters/` contains app-specific integration adapters:
  - `mpris_adapter.cr` owns `MPRIS::Service`, callback registration, playback-state mapping, current MPRIS song/artwork state, and position sync throttling
  - `lastfm_adapter.cr` owns Last.fm client/scrobbler construction and playback sync
- `src/ext/mpris` contains a small Crystal MPRIS/DBus implementation kept separate from Qt-specific app code
- `src/ext/lastfm` contains the Last.fm API client, request signing, scrobble timing, and retry cache
- One MPD client handles commands and status reads
- A separate callback-enabled MPD listener pushes live updates from the server
- `EventBridge` marshals callback-thread updates safely onto the Qt main thread
- `Settings` wraps `QSettings` persistence for connection details, UI visibility preferences, visualizer configuration, layout size, and splitter state
- The UI uses Qt Widgets directly, including `QMainWindow`, menus/actions, push buttons, sliders, splitters, tree views, custom `QAbstractItemModel` models, custom item delegates, event filters, shortcuts, and graphics effects

## License

MIT
