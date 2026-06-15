require "../src/lrclib"

artist = ARGV[0]? || "Nirvana"
title = ARGV[1]? || "Come As You Are"
album = ARGV[2]? || (ARGV.empty? ? "Nevermind" : nil)
duration = ARGV[3]?.try(&.to_i?) || (ARGV.empty? ? 219 : nil)

client = LRCLIB::Client.new

lyrics = client.get(
  artist_name: artist,
  track_name: title,
  album_name: album,
  duration: duration
)

unless lyrics
  puts "No lyrics found"
  exit
end

puts "#{lyrics.artist_name} - #{lyrics.track_name}"
puts lyrics.album_name if lyrics.album_name
puts

synced_lines = lyrics.synced_lines
if !synced_lines.empty?
  synced_lines.each do |line|
    puts "[#{line.time}] #{line.text}"
  end
elsif plain_lyrics = lyrics.plain_lyrics
  puts plain_lyrics
elsif lyrics.instrumental?
  puts "Instrumental track"
else
  puts "Lyrics response did not include lyric text"
end
