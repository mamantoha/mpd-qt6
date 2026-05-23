require "spec"
require "../src/mime_magic"

describe MimeMagic do
  fixtures = File.join(__DIR__, "fixtures")

  {
    "one_pixel.jpg"  => "image/jpeg",
    "one_pixel.png"  => "image/png",
    "one_pixel.gif"  => "image/gif",
    "one_pixel.webp" => "image/webp",
    "one_pixel.jxl"  => "image/jxl",
  }.each do |file, mime_type|
    it "detects #{mime_type} from #{file}" do
      bytes = File.read(File.join(fixtures, file)).to_slice

      MimeMagic.by_magic(bytes).should eq(mime_type)
    end
  end

  it "returns nil for unknown bytes" do
    MimeMagic.by_magic(Bytes[0x00, 0x01, 0x02, 0x03]).should be_nil
  end
end
