# TODO

Planning reference for useful missing features and polish ideas.

## High Value

- [ ] Add queue search/filter for large playlists.
- [ ] Collapse or expand all artists/albums.
- [ ] Jump to the currently playing song in the library.
- [ ] Remember expanded library tree nodes between reloads.
- [x] Add MPD saved playlist support.
- [x] List saved playlists.
- [x] Load a playlist into the queue.
- [x] Append a playlist to the queue.
- [x] Save the current queue as a playlist.
- [x] Rename saved playlists.
- [x] Delete saved playlists.
- [x] Remove songs from saved playlists.
- [x] Add songs from saved playlists to the queue.
- [x] Replace the queue with a saved playlist.
- [x] Drag queue songs into saved playlists.
- [x] Reorder songs inside saved playlists.
- [ ] Move selected queue songs to top or bottom.
- [x] Add selected queue songs to a saved playlist from the queue context menu.
- [x] Play selected queue song now.
- [x] Remove selected queue songs.
- [x] Clear the current queue.
- [x] Save the current queue as a playlist from the queue context menu.
- [x] Scroll the queue to the current song.
- [ ] Play selected song/album/artist now.
- [x] Replace queue with selected song/album/artist.
- [x] Add selected library item to the queue.
- [x] Add MPD output/device control for enabling and disabling outputs.
- [ ] Extract the embedded MPRIS implementation in `src/ext/mpris` into a standalone shard.
- [ ] Add proper repeat-current-track support.
- [ ] Expose MPD `single` mode in the UI.
- [ ] Map MPRIS `LoopStatus=Track` to MPD `repeat=true` and `single=true`.
- [x] Map MPRIS `LoopStatus=Playlist` to MPD `repeat=true`.
- [x] Map MPRIS `LoopStatus=None` to MPD `repeat=false`.

## User Workflow

- [ ] Add named connection profiles for multiple MPD servers.
- [ ] Add recently played history with quick re-add/play actions.
- [ ] Add optional confirmation for destructive queue actions such as clearing the queue.
- [ ] Reset/disconnect the stored Last.fm session.
- [ ] Show the last scrobble status in Settings or the status bar.
- [x] Add a manual Last.fm authentication action.

## Keyboard And Input Polish

- [ ] Space for play/pause.
- [ ] Left/Right for seeking.
- [ ] Ctrl+Up/Ctrl+Down for volume.
- [ ] `/` as an alternate library search shortcut.
- [ ] Enter to play the selected database song.
- [x] Ctrl+F to open library search.
- [x] Esc to close focused library search.
- [x] Enter to play the selected queue song.
- [x] Delete to remove selected queue songs.
- [x] Delete to remove selected stored playlist songs.
- [x] Support mouse wheel volume changes over the volume button and volume popup.
- [ ] Support keyboard seek steps on the progress slider.
- [ ] Add larger seek steps with Shift+Left/Shift+Right.
