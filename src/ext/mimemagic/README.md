# MimeMagic

Small Crystal helper for detecting MIME types from file magic bytes.

This code is currently embedded in `mpd-qt6` under `src/ext/mimemagic` as a
candidate for a future standalone shard.

## Purpose

`MimeMagic` detects a file type from the first bytes of binary data. It does not
decode files and does not inspect file extensions.

In `mpd-qt6`, it is used by cover-art caching so cached image bytes can still
provide a useful MIME type such as `image/jpeg` or `image/png`.

## Supported Types

Current supported MIME types:

- `image/jpeg`
- `image/png`
- `image/gif`
- `image/webp`
- `image/jxl`

More signatures can be added later as needed.

## Usage

```crystal
require "./src/mime_magic"

bytes = File.read("cover.jpg").to_slice
mime_type = MimeMagic.by_magic(bytes)

case mime_type
when "image/jpeg"
  puts "JPEG image"
when "image/png"
  puts "PNG image"
when nil
  puts "Unknown file type"
end
```

`MimeMagic.by_magic` returns `String?`: the detected MIME type, or `nil` when
the bytes do not match a known signature.

## Specs

Specs live in `spec/` and use real 1x1 image fixtures from `spec/fixtures`.

Run from the repository root:

```sh
crystal spec src/ext/mimemagic/spec
```

## Fixture Images

The fixture images are real 1x1 pixel files.

They were generated with ImageMagick:

```sh
magick -size 1x1 xc:red spec/fixtures/one_pixel.png
magick -size 1x1 xc:red spec/fixtures/one_pixel.jpg
magick -size 1x1 xc:red spec/fixtures/one_pixel.gif
magick -size 1x1 xc:red spec/fixtures/one_pixel.webp
```

The JPEG XL fixture was generated from the PNG fixture with `cjxl`:

```sh
cjxl spec/fixtures/one_pixel.png spec/fixtures/one_pixel.jxl
```

Use `file spec/fixtures/one_pixel.*` to verify the generated files.
