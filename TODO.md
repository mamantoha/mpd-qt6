# TODO

Planning reference for useful missing features and polish ideas.

## High Value

- Add database search/filter by artist, album, title, and file path.
- Add queue search/filter for large playlists.
- Add MPD saved playlist support:
  - list saved playlists
  - load a playlist into the queue
  - append a playlist to the queue
  - save the current queue as a playlist
  - rename or delete playlists where supported
- Add queue context menu actions:
  - play selected song now
  - remove selected songs
  - move selected songs to top or bottom
  - show song details
  - add selected songs to a saved playlist
- Add MPD output/device control for enabling and disabling outputs.

## User Workflow

- Add song details dialog for selected or currently playing songs:
  - title, artist, album, date, genre
  - file path or URI
  - duration
  - track and disc number
  - available audio details from MPD
- Add named connection profiles for multiple MPD servers.
- Add recently played history with quick re-add/play actions.

## Keyboard And Input Polish

- Add global app shortcuts:
  - Space for play/pause
  - Left/Right for seeking
  - Ctrl+Up/Ctrl+Down for volume
  - Ctrl+F or `/` for search focus
  - Enter to play the selected queue/database song
- Support mouse wheel volume changes over the volume button or slider.
- Support keyboard seek steps on the progress slider.
- Add larger seek steps with Shift+Left/Shift+Right.
