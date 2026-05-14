# LastFM

Small Crystal Last.fm client and scrobbling state machine.

This code lives inside `mpd-qt6` for now, but it is intentionally written like
a separate shard. It does not depend on Qt, MPD, or application settings. A
player application owns credentials and playback state, then feeds plain song
metadata into `LastFM::Scrobbler`.

## What It Provides

- Last.fm API request signing.
- JSON Last.fm API calls over `https://ws.audioscrobbler.com/2.0/`.
- Username/password exchange for a reusable mobile session key.
- `track.updateNowPlaying` support.
- `track.scrobble` support.
- Scrobbling threshold logic.
- Duplicate prevention for the current playing track.
- Disk cache for failed scrobbles, with later retry.

## Data Flow

The application remains the source of truth for playback:

1. The player receives metadata and playback status from its own backend.
2. The player calls `scrobbler.update(...)` when song, state, elapsed time, or
   duration changes.
3. The scrobbler normalizes the metadata into a `LastFM::Track`.
4. When a new valid track starts, the scrobbler sends "now playing".
5. When playback reaches the Last.fm threshold, the scrobbler submits a scrobble.
6. If scrobbling fails, the record is cached on disk and retried later.

The Last.fm module does not control playback and does not know how the player
stores settings. It only needs callbacks for "is scrobbling enabled?" and "what
is the current session key?".

## Authentication

Last.fm write APIs require an API key, shared secret, and user session key.

Applications should ask the user for their Last.fm username/password once, call
`Client#mobile_session`, then store the returned session key. Future scrobbling
uses the session key instead of the password.

```crystal
client = LastFM::Client.new(api_key, shared_secret)
session = client.mobile_session(username, password)

settings.lastfm_username = session.username
settings.lastfm_session_key = session.key
settings.save
```

## Basic Usage

```crystal
require "./src/lastfm"

client = LastFM::Client.new(api_key, shared_secret)

scrobbler = LastFM::Scrobbler.new(
  "my-player",
  -> { settings.lastfm_enabled? },
  -> { settings.lastfm_session_key },
  client
)

song = {
  "Artist"   => "Eminem",
  "Title"    => "Beautiful",
  "Album"    => "Curtain Call 2",
  "Track"    => "03",
  "duration" => "393",
  "file"     => "Eminem/Curtain Call 2/03 Beautiful.ogg",
}

scrobbler.update(song, "play", elapsed: 0.0, duration: 393.0)
scrobbler.update(song, "play", elapsed: 200.0, duration: 393.0)
scrobbler.update(song, "pause", elapsed: 205.0, duration: 393.0)
scrobbler.update(nil, "stop", elapsed: 0.0, duration: 0.0)
```

The first update sends "now playing". The second update crosses the scrobbling
threshold and submits the scrobble. Pause updates keep the current state, while
stop clears the current track.

## Scrobbling Rules

`LastFM::Track#scrobbleable?` requires:

- non-empty artist
- non-empty title
- duration greater than 30 seconds

The scrobble threshold is:

- half the track duration, or
- 4 minutes

whichever comes first.

This matches common desktop player behavior.

## Failed Scrobble Cache

Failed scrobbles are stored as JSON records, not music files.

The cache path is:

```text
$XDG_CACHE_HOME/<cache_name>/lastfm_scrobbles.json
```

If `XDG_CACHE_HOME` is not set, the fallback is:

```text
~/.cache/<cache_name>/lastfm_scrobbles.json
```

The `cache_name` is the first argument passed to `LastFM::Scrobbler.new`.

## API

### `LastFM::Client`

```crystal
client = LastFM::Client.new(api_key, shared_secret)
```

Main methods:

- `mobile_session(username, password) : LastFM::Session`
- `update_now_playing(track, session_key) : Nil`
- `scrobble(track, session_key) : Nil`

### `LastFM::Scrobbler`

```crystal
scrobbler = LastFM::Scrobbler.new(cache_name, enabled, session_key, client)
```

Constructor arguments:

- `cache_name` names the cache directory.
- `enabled` is a callback returning whether scrobbling is enabled.
- `session_key` is a callback returning the current Last.fm session key.
- `client` is a `LastFM::Client`.

Main methods:

- `update(song, state, elapsed, duration) : Nil`
- `authenticate(username, password) : LastFM::Session`

## Metadata Input

`Scrobbler#update` accepts `Hash(String, String)?` so it can be fed directly
from different music players.

Recognized keys:

- `Artist`
- `Title`
- `Album`
- `Track`
- `duration`
- `Time`
- `Id`
- `file`

Only `Artist` and `Title` are required for a scrobbleable track. Duration can be
passed as the `duration` argument or read from metadata.

## Error Handling

`LastFM::Client` raises `LastFM::Error` when Last.fm rejects a request or when
HTTP/JSON handling fails.

`LastFM::Scrobbler` catches network/API failures for background scrobbling and
caches failed scrobble records for retry. Authentication errors are returned to
the caller through `LastFM::Error`.

## Notes

- The module uses Last.fm form-encoded POST requests with `format=json`.
- API credentials are not embedded; pass them to `LastFM::Client`.
- Background network calls are started with `Thread.new`.
- The module is currently embedded in `mpd-qt6`, but the public surface is small
  enough to extract into a separate shard later.
