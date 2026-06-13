module MPDUI
  record LyricsLine, time : Time::Span, text : String

  class LyricsResult
    getter synced_lines : Array(LyricsLine)
    getter plain_text : String?
    getter instrumental : Bool

    def self.from_lrclib(lyrics : LRCLIB::Lyrics) : self
      synced_lines = lyrics.synced_lines.map do |line|
        LyricsLine.new(line.time, line.text)
      end

      new(
        synced_lines: synced_lines,
        plain_text: normalize_text(lyrics.plain_lyrics),
        instrumental: lyrics.instrumental?
      )
    end

    def initialize(
      @synced_lines : Array(LyricsLine) = [] of LyricsLine,
      @plain_text : String? = nil,
      @instrumental : Bool = false
    )
    end

    def synced? : Bool
      !synced_lines.empty?
    end

    def plain? : Bool
      !plain_text.to_s.strip.empty?
    end

    def empty? : Bool
      !synced? && !plain? && !instrumental
    end

    def active_line_index(position : Time::Span) : Int32?
      index = synced_lines.rindex { |line| line.time <= position }
      index if index && index >= 0
    end

    private def self.normalize_text(value : String?) : String?
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
