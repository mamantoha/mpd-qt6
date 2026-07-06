require "file_utils"

module MPDUI
  class CacheInfo
    record Entry,
      label : String,
      path : String,
      files : Int32,
      bytes : Int64

    def self.entries(cache_name : String = Settings::CACHE_PREFIX) : Array(Entry)
      cache_root = File.join(cache_home, cache_name)

      [
        directory_entry("Cover art", File.join(cache_root, "covers")),
        directory_entry("Lyrics", File.join(cache_root, "lyrics")),
        file_entry("Failed Last.fm scrobbles", File.join(cache_root, "lastfm_scrobbles.json")),
      ]
    end

    def self.cache_home : String
      ENV["XDG_CACHE_HOME"]? || File.join(ENV["HOME"]? || Dir.tempdir, ".cache")
    end

    def self.delete(entry : Entry) : Nil
      if Dir.exists?(entry.path)
        FileUtils.rm_rf(entry.path)
      elsif File.file?(entry.path)
        File.delete(entry.path)
      end
    end

    private def self.directory_entry(label : String, path : String) : Entry
      files = 0
      bytes = 0_i64

      if Dir.exists?(path)
        Dir.glob(File.join(path, "**", "*")).each do |entry_path|
          next unless File.file?(entry_path)

          files += 1
          bytes += File.size(entry_path)
        end
      end

      Entry.new(label, path, files, bytes)
    end

    private def self.file_entry(label : String, path : String) : Entry
      files = File.file?(path) ? 1 : 0
      bytes = files == 1 ? File.size(path) : 0_i64

      Entry.new(label, path, files, bytes)
    end
  end
end
