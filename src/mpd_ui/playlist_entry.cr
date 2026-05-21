module MPDUI
  record PlaylistEntry, name : String, last_modified : String? do
    def self.from_mpd(metadata : Hash(String, String)) : self?
      name = metadata["playlist"]?.try(&.strip)
      return if name.nil? || name.empty?

      new(name, metadata["Last-Modified"]?)
    end

    def tooltip : String
      if value = last_modified
        value.empty? ? name : "Last modified: #{value}"
      else
        name
      end
    end
  end
end
