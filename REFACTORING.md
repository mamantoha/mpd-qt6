# Refactoring Plan

This document tracks technical simplifications for `mpd-qt6`. The goal is to keep the current behavior stable while making the code easier to read, reason about, and change.

The app is already feature-complete enough for daily use. The main problem is not missing features, but that most features grew around one shared `MPDUI::App` object with many instance variables. The safest path is to extract small, plain Crystal objects step by step.

## Goals

- Keep the UI and behavior unchanged while refactoring.
- Reduce shared mutable state in `MPDUI::App`.
- Replace raw `Hash(String, String)` MPD metadata with small domain objects.
- Separate Qt widget construction from MPD commands and background work.
- Make background-thread and Qt-main-thread boundaries obvious.
- Keep external-ready modules under `src/ext` independent from Qt-specific app code.

## Non-goals

- Do not rewrite the whole app at once.
- Do not introduce a framework or dependency-injection system.
- Do not change the visual design as part of refactoring.
- Do not change the MPRIS or Last.fm public behavior unless a refactor exposes a real bug.

## Current Pain Points

### 1. `MPDUI::App` Owns Too Much

`src/mpd_ui/app.cr` declares the main app class and a large set of widget references, playback state, queue state, database state, service objects, event filters, and layout settings.

Feature modules under `src/mpd_ui/app/` split the file layout, but they still operate on the same shared instance variables. This makes each module harder to understand because any method may depend on state created elsewhere.

### 2. Raw MPD Hashes Are Used Everywhere

Songs are passed around as `Hash(String, String)`. This requires every feature to know MPD field names such as `Title`, `Artist`, `Album`, `Track`, `Disc`, `Time`, and `file`.

This affects playback display, queue rows, database sorting, MPRIS metadata, Last.fm scrobbling, tooltips, and cover-art caching.

### 3. Player Code Mixes Many Responsibilities

`src/mpd_ui/app/player.cr` currently handles playback refresh, progress state, volume state, button syncing, cover-art loading, cover caching, MPRIS cover temp files, blurred background rendering, and UI updates.

These are related at runtime, but they do not need to live in one module.

### 4. Queue and Library Code Mix Views with Commands

`queue.cr` and `database.cr` both create Qt widgets, build models, handle selection, handle drag/drop, and execute MPD commands.

The code would be easier to read if view helpers, model building, and command logic were separate.

### 5. Background Work Is Scattered

Several places use `Thread.new` and `@qt_app.invoke_later` directly. That works, but shutdown checks and error handling are repeated in different styles.

## Refactoring Steps

### Step 1: Add Domain Objects

Status: complete.

Add:

- `src/mpd_ui/song.cr`
- `src/mpd_ui/playback_state.cr`

`Song` should wrap MPD metadata and expose typed helpers:

- `file`
- `title`
- `artist`
- `album`
- `album_artist`
- `duration`
- `track_number`
- `disc_number`
- `date`
- `display_title`
- `display_artist`
- `tooltip_html`

`PlaybackState` should hold:

- MPD state: play, pause, stop
- current song
- current queue position
- elapsed
- duration
- random
- repeat
- volume
- playlist version

Expected result:

- Less repeated raw hash access.
- Easier MPRIS and Last.fm mapping.
- Safer sorting and display code.

Suggested first usage:

- Convert `FormatHelpers` methods to accept `Song` where practical.
- Keep compatibility helpers for raw hashes during transition.

Current progress:

- Added `Song`.
- Added `PlaybackState`.
- Routed shared formatting, duration, queue title, database label, track/disc parsing, and song tooltip helpers through `Song`.
- Kept raw `Hash(String, String)` helper overloads so existing UI code can be migrated gradually.
- Migrated player display, MPRIS sync, Last.fm sync, cover-art cache keys, queue row display, and database row display/sorting to use `Song`.
- Added `@playback_state` and keep it synchronized with existing scalar playback fields as a transition step.
- Migrated loaded database storage to `Array(Song)` and moved database grouping/filtering/album summaries to `Song`.
- Migrated MPD status refresh current-song and playlist results to `Song`, so queue refresh now consumes `Array(Song)`.
- Migrated read-only playback consumers to `PlaybackState`: progress display/seek tooltip, playback controls, queue current-track icon, toggle button sync, MPRIS sync, and Last.fm sync.
- Made `PlaybackState` the primary playback state by removing the old scalar playback fields from `App`.
- Removed raw-hash song helper compatibility overloads from `FormatHelpers`; app song display helpers now expect `Song`.

### Step 2: Extract Cover Art Service

Status: complete.

Add:

- `src/mpd_ui/cover_art_service.cr`

Move from `player.cr`:

- MPD `readpicture` / `albumart` fetching
- disk cache path/key generation
- MIME detection
- cache read/write

Keep Qt pixmap rendering outside this service. The service should return bytes plus metadata only.

Expected API shape:

```crystal
service = CoverArtService.new(host, port, cache_name)
result = service.fetch(song)
```

Expected result:

- `player.cr` no longer knows how cover bytes are fetched.
- Cover cache behavior becomes easy to test.
- Future standalone cover-art logic is possible.

Current progress:

- Added `CoverArtService`.
- Moved MPD `readpicture` / `albumart` fetching to the service.
- Moved persistent disk cache key/path generation to the service.
- Moved cache read/write and MIME detection to the service.
- Kept Qt pixmap rendering, cover tooltip HTML, blurred background rendering, and MPRIS temp cover file handling in `player.cr`.

### Step 3: Add a Small Background Helper

Status: complete.

Add:

- `src/mpd_ui/background_task.cr`

Purpose:

- centralize `Thread.new`
- centralize `@qt_app.invoke_later`
- avoid repeating `@quitting` checks and rescue blocks everywhere

Possible shape:

```crystal
run_background do
  fetch_data
end.on_success do |data|
  apply_to_ui(data)
end.on_error do |error|
  show_error(error)
end
```

This can start very small. It does not need to be a generic framework.

Expected result:

- Easier to see which code runs on a worker thread.
- Easier to see which code runs on the Qt main thread.
- Fewer shutdown-related edge cases.

Current progress:

- Added `BackgroundTask#run_background`.
- Migrated status refresh to `run_background`.
- Migrated cover-art fetch to `run_background`.
- Migrated database load/update to `run_background`.
- Left the MPD callback listener as a direct `Thread.new` because it is a long-lived listener, not a short background task.
- Left direct `invoke_later` calls in MPRIS callbacks, tray restore actions, and `EventBridge` because those are already explicit UI-thread handoffs rather than background task results.

### Step 4: Extract Player Header View

Status: complete.

Add:

- `src/mpd_ui/views/player_header_view.cr`

Move from `app.cr`:

- cover label
- title/subtitle labels
- options button placement
- progress slider and time label
- playback control buttons
- volume menu
- blurred background label/effect
- progress tooltip event filter
- album-art click filter

The view should expose callbacks/signals or simple properties:

- `on_play_pause`
- `on_previous`
- `on_next`
- `on_shuffle_changed`
- `on_repeat_changed`
- `on_seek`
- `on_volume_changed`
- `on_cover_clicked`

Expected result:

- `build_ui` becomes much smaller.
- UI layout can be understood without reading MPD logic.
- Player logic can update the header through named methods.

Current progress:

- Added `PlayerHeaderView`.
- Moved playback header layout from `App#build_ui` into the view.
- Moved cover label, title/subtitle labels, progress slider, time label, playback buttons, volume menu, options button, blurred background label/effect, progress tooltip filter, and album-art click filter into the view.
- Exposed command callbacks for previous, play/pause, next, shuffle, repeat, seek, volume, and cover click.
- Kept MPD command execution and playback state ownership in `App`.

### Step 5: Extract Player Controller

Add:

- `src/mpd_ui/controllers/player_controller.cr`

Responsibilities:

- consume MPD status snapshots
- update `PlaybackState`
- decide when current song changed
- request cover art
- sync MPRIS and Last.fm
- update `PlayerHeaderView`
- update queue indicators when song/state changes

Expected result:

- `AppPlayer` can shrink or disappear.
- Playback logic becomes easier to follow from one controller.

### Step 6: Extract Queue View and Queue Controller

Add:

- `src/mpd_ui/views/queue_view.cr`
- `src/mpd_ui/controllers/queue_controller.cr`

`QueueView` should own:

- `QTreeView`
- `StandardItemModel`
- context menu
- keyboard shortcuts
- selection helpers
- row indicator updates
- visual/header configuration

`QueueController` should own:

- play selected row
- remove selected rows
- clear queue
- reorder selected rows
- append/insert database selection into queue

Expected result:

- Drag/drop code becomes easier to isolate.
- Queue rendering and MPD queue commands stop being interleaved.

### Step 7: Extract Library Index and Library View

Add:

- `src/mpd_ui/library_index.cr`
- `src/mpd_ui/views/library_view.cr`
- optionally `src/mpd_ui/controllers/library_controller.cr`

`LibraryIndex` should own:

- filtering
- artist/album/song grouping
- album sort by year
- song sort by disc and track

`LibraryView` should own:

- search panel
- tree view
- item delegate
- context menu
- drag source
- selected URI collection

Expected result:

- Library sorting/filtering becomes testable without Qt.
- `database.cr` becomes smaller and easier to navigate.

### Step 8: Clarify Service Adapters

Keep generic modules in `src/ext`:

- `src/ext/mpris`
- `src/ext/lastfm`

Keep app-specific glue in:

- `src/mpd_ui/app/mpris.cr`
- `src/mpd_ui/app/lastfm.cr`

Later, rename app glue to adapter classes:

- `MprisAdapter`
- `LastfmAdapter`

Expected result:

- It becomes clear which code is reusable shard code and which code is app integration.

### Step 9: Reduce `App` to Composition Root

After the extractions above, `MPDUI::App` should mostly:

- load settings
- create Qt application/window
- create views/controllers/services
- connect signals between objects
- start MPD connection
- run the Qt event loop
- save layout settings on quit

Expected result:

- `App` becomes the place where objects are wired together, not the place where every feature is implemented.

## Suggested Order

1. Add `Song` and keep raw-hash compatibility.
2. Move cover-art fetch/cache to `CoverArtService`.
3. Add a small background helper.
4. Extract `PlayerHeaderView`.
5. Extract `PlayerController`.
6. Extract `QueueView`.
7. Extract `QueueController`.
8. Extract `LibraryIndex`.
9. Extract `LibraryView`.
10. Convert MPRIS and Last.fm glue into adapter classes.
11. Simplify `MPDUI::App`.

## Validation Strategy

After each step:

- Build with `shards build`.
- Manually verify:
  - startup and MPD connection
  - play/pause/previous/next
  - queue refresh and current-song indicator
  - queue drag/drop reorder
  - database load/search/add-to-queue
  - album art, blurred background, and cover tooltip
  - MPRIS metadata and controls
  - Last.fm now-playing/scrobbling if enabled
  - quit behavior

Add focused specs when logic becomes independent from Qt, especially for:

- `Song` parsing
- track/disc/year parsing
- library grouping/sorting
- cover-art cache keys
- Last.fm scrobble timing

## Notes

Prefer small pull requests. A good refactor PR should move one responsibility and keep behavior unchanged.

If a step starts requiring many unrelated edits, split it again. The purpose is readability, not a large architectural rewrite.
