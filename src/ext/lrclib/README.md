# LRCLIB

A small Crystal client for the public [LRCLIB](https://lrclib.net/) lyrics API.

It fetches plain lyrics, synced LRC lyrics, and parsed timestamped lyric lines
from LRCLIB using track metadata.

## Installation

When used as a shard, add it to `shard.yml`:

```yaml
dependencies:
  lrclib:
    github: your-org/lrclib
```

Then run:

```sh
shards install
```

## Usage

```crystal
require "lrclib"

client = LRCLIB::Client.new

lyrics = client.get(
  artist_name: "Nirvana",
  track_name: "Come As You Are",
  album_name: "Nevermind",
  duration: 219
)

if lyrics
  puts lyrics.plain_lyrics

  lyrics.synced_lines.each do |line|
    puts "#{line.time}: #{line.text}"
  end
else
  puts "No lyrics found"
end
```

`album_name` and `duration` are optional, but passing them can improve match
quality when the metadata is accurate.

## API

### `LRCLIB::Client`

```crystal
client = LRCLIB::Client.new
```

Optional arguments:

```crystal
client = LRCLIB::Client.new(
  base_url: "https://lrclib.net",
  user_agent: "MyApp"
)
```

### `Client#get`

```crystal
lyrics = client.get(
  artist_name: "Muse",
  track_name: "Starlight",
  album_name: "Black Holes and Revelations",
  duration: 240
)
```

Returns `LRCLIB::Lyrics?`.

Returns `nil` when LRCLIB has no match. Raises `LRCLIB::Error` for unexpected
HTTP, JSON, or network failures.

### `Client#get_cached`

```crystal
lyrics = client.get_cached(
  artist_name: "Muse",
  track_name: "Starlight",
  album_name: "Black Holes and Revelations",
  duration: 240
)
```

Returns `LRCLIB::Lyrics?`.

This uses LRCLIB's `/api/get-cached` endpoint. It only searches LRCLIB's
internal database and does not attempt external lyric sources.

### `Client#get_by_id`

```crystal
lyrics = client.get_by_id(3396226)
```

Returns `LRCLIB::Lyrics?`.

This is useful when an application stores LRCLIB record IDs and wants to fetch
the exact record later.

### `Client#search`

```crystal
results = client.search(q: "still alive portal")
```

Or search by structured fields:

```crystal
results = client.search(
  track_name: "Starlight",
  artist_name: "Muse",
  album_name: "Black Holes and Revelations"
)
```

Returns `Array(LRCLIB::Lyrics)`.

LRCLIB currently returns a limited number of results and does not paginate
search responses.

### `LRCLIB::Lyrics`

Important fields:

- `track_name`
- `artist_name`
- `album_name`
- `duration`
- `instrumental?`
- `plain_lyrics`
- `synced_lyrics`
- `synced_lines`

`synced_lines` returns parsed `LRCLIB::SyncedLine` values:

```crystal
lyrics.synced_lines.each do |line|
  puts line.time
  puts line.text
end
```

## Notes

Do not store copyrighted lyric text in source files or fixtures. Applications
should fetch lyrics at runtime and cache them in a user-specific cache
directory when caching is needed.
