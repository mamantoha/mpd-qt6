module MimeMagic
  def self.by_magic(bytes : Bytes) : String?
    case
    when jpeg?(bytes)
      "image/jpeg"
    when png?(bytes)
      "image/png"
    when gif?(bytes)
      "image/gif"
    when webp?(bytes)
      "image/webp"
    when jpeg_xl?(bytes)
      "image/jxl"
    end
  end

  private def self.jpeg?(bytes : Bytes) : Bool
    bytes.size >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff
  end

  private def self.png?(bytes : Bytes) : Bool
    bytes.size >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47
  end

  private def self.gif?(bytes : Bytes) : Bool
    bytes.size >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61
  end

  private def self.webp?(bytes : Bytes) : Bool
    bytes.size >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50
  end

  private def self.jpeg_xl?(bytes : Bytes) : Bool
    jpeg_xl_codestream?(bytes) || jpeg_xl_container?(bytes)
  end

  private def self.jpeg_xl_codestream?(bytes : Bytes) : Bool
    bytes.size >= 2 &&
      bytes[0] == 0xff &&
      bytes[1] == 0x0a
  end

  private def self.jpeg_xl_container?(bytes : Bytes) : Bool
    bytes.size >= 12 &&
      bytes[0] == 0x00 &&
      bytes[1] == 0x00 &&
      bytes[2] == 0x00 &&
      bytes[3] == 0x0c &&
      bytes[4] == 0x4a &&
      bytes[5] == 0x58 &&
      bytes[6] == 0x4c &&
      bytes[7] == 0x20 &&
      bytes[8] == 0x0d &&
      bytes[9] == 0x0a &&
      bytes[10] == 0x87 &&
      bytes[11] == 0x0a
  end
end
