# LRCLIB

Small Crystal wrapper around the public LRCLIB lyrics API.

This directory is kept independent from Garnetune application code so it can
later be extracted into a separate shard.

## Data Flow

1. The player passes normalized song metadata to `LRCLIB::Client`.
2. The client calls LRCLIB over HTTP and parses the JSON response.
3. The client returns an `LRCLIB::Lyrics` object with plain lyrics, synced LRC
   text, and parsed timestamped lines.
4. The host application decides how to cache, display, and synchronize the
   lyrics with playback.

## Basic Usage

```crystal
require "./src/lrclib"

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

`duration` is optional, but passing it helps LRCLIB choose a better match.

Do not store copyrighted lyric text in source files or fixtures. Applications
should fetch lyrics at runtime and cache them in the user's cache directory.
