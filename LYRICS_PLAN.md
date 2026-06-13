# Lyrics Support Plan

Goal: add LRCLIB-backed lyrics support with caching and synced lyric display using standard Qt model/view components.

## 1. Add LRCLIB External Module

- [x] Create `src/ext/lrclib/src/lrclib.cr`.
- [x] Add `LRCLIB::Client` for HTTP API access.
- [x] Add response objects for synced and plain lyrics.
- [x] Parse LRCLIB JSON responses into Crystal objects.
- [x] Keep this module independent from Garnetune app code so it can become a separate shard later.
- [x] Add `src/ext/lrclib/README.md` with basic usage and data flow.

## 2. Add Lyrics Domain Objects

- [ ] Add app-level lyrics types, for example `LyricsLine` and `LyricsResult`.
- [ ] Store synced lyrics as timestamped rows.
- [ ] Store unsynced lyrics as plain text.
- [ ] Keep LRCLIB-specific response details out of UI code.

## 3. Add Lyrics Cache

- [ ] Store fetched lyrics in the app cache directory.
- [ ] Use a stable cache key based on artist, title, and duration.
- [ ] Cache both found lyrics and "not found" results to avoid repeated lookups.
- [ ] Add a way to invalidate or ignore stale cache entries if needed later.

## 4. Add Lyrics Service

- [ ] Add `LyricsService` for app-specific lookup logic.
- [ ] Fetch lyrics in a background execution context.
- [ ] Read from cache before calling LRCLIB.
- [ ] Save successful LRCLIB responses to cache.
- [ ] Notify UI when lyrics are loading, found, not found, or failed.
- [ ] Cancel or ignore stale requests when the current song changes.

## 5. Add Lyrics Model

- [ ] Add `LyricsModel < Qt6::AbstractListModel`.
- [ ] Store all synced lyric lines in the model.
- [ ] Return lyric text through the standard display role.
- [ ] Expose timestamp data through an app-specific user role if needed.
- [ ] Support clearing/replacing lyrics efficiently.

## 6. Add Lyrics View

- [ ] Add a `LyricsView` built around `QListView`.
- [ ] Show all synced lyric rows.
- [ ] Highlight the currently active lyric row.
- [ ] Auto-scroll when the active line changes.
- [ ] Add read-only plain text fallback for unsynced lyrics.
- [ ] Add loading, empty, and error states.
- [ ] Add `Copy Lyrics` context menu action and `Ctrl+C` support. (not neccessary, can be added later)

## 7. Wire Playback Position To Lyrics

- [ ] Update active lyric row when playback position changes.
- [ ] Avoid work when the active row did not change.
- [ ] Reset highlighted line when playback stops or song changes.
- [ ] Keep user interaction smooth during frequent progress updates.

## 8. Add UI Entry Point

- [ ] Add a `Lyrics` between to `Library` and `Playlists`. (hidden by default)
- [ ] Load lyrics for the current song when the tab is visible.
- [ ] Continue syncing lyrics while the tab is visible.
- [ ] Decide whether lyrics should be fetched eagerly on song change or lazily when the tab opens.

## 9. Add Settings

- [ ] Add setting to enable or disable online lyrics.
- [ ] Add setting for synced lyrics auto-scroll if useful.
- [ ] Keep LRCLIB as the default provider. (not neccessary, can be added later)
- [ ] Leave room for future providers without changing the UI structure. (not neccessary, can be added later)

## 10. Polish And Documentation

- [ ] Update `README.md` feature list.
- [ ] Document LRCLIB cache behavior.
- [ ] Document that lyrics are fetched from LRCLIB and may be unavailable for some tracks.
- [ ] Remove temporary debug output.
- [ ] Build with `shards build -Dpreview_mt -Dexecution_context`.
