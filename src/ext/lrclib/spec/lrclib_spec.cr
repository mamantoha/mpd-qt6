require "http/server"
require "spec"
require "../src/lrclib"

describe LRCLIB do
  json = <<-JSON
    {
      "id": 123,
      "trackName": "Demo Track",
      "artistName": "Demo Artist",
      "albumName": "Demo Album",
      "duration": 185,
      "instrumental": false,
      "plainLyrics": "First line\\nSecond line",
      "syncedLyrics": "[00:01.50] First line\\n[01:02.03] Second line"
    }
    JSON

  describe LRCLIB::Lyrics do
    it "parses LRCLIB JSON responses" do
      lyrics = LRCLIB::Lyrics.from_json(json)

      lyrics.id.should eq(123)
      lyrics.track_name.should eq("Demo Track")
      lyrics.artist_name.should eq("Demo Artist")
      lyrics.album_name.should eq("Demo Album")
      lyrics.duration.should eq(185)
      lyrics.instrumental.should be_false
      lyrics.plain_lyrics.should eq("First line\nSecond line")
      lyrics.synced_lyrics.should eq("[00:01.50] First line\n[01:02.03] Second line")
      lyrics.has_lyrics?.should be_true
    end

    it "parses synced lyric timestamps" do
      lyrics = LRCLIB::Lyrics.from_json(json)
      lines = lyrics.synced_lines

      lines.size.should eq(2)
      lines[0].time.should eq(1.5.seconds)
      lines[0].text.should eq("First line")
      lines[1].time.should eq(62.03.seconds)
      lines[1].text.should eq("Second line")
    end

    it "handles instrumental responses without lyric text" do
      lyrics = LRCLIB::Lyrics.from_json(%({"trackName":"Demo","artistName":"Artist","instrumental":true}))

      lyrics.instrumental.should be_true
      lyrics.has_lyrics?.should be_false
      lyrics.synced_lines.should be_empty
    end
  end

  describe LRCLIB::Client do
    it "fetches lyrics and sends track metadata as query parameters" do
      request_resource = Channel(String).new(1)

      handler = ->(context : HTTP::Server::Context) do
        request_resource.send(context.request.resource)
      end

      with_server(json, handler: handler) do |base_url|
        client = LRCLIB::Client.new(base_url, user_agent: "lrclib-spec")
        lyrics = client.get(
          artist_name: "Demo Artist",
          track_name: "Demo Track",
          album_name: "Demo Album",
          duration: 185
        )

        lyrics.should_not be_nil
        lyrics.not_nil!.track_name.should eq("Demo Track")
        request_resource.receive.should eq("/api/get?artist_name=Demo+Artist&track_name=Demo+Track&album_name=Demo+Album&duration=185")
      end
    end

    it "returns nil when LRCLIB has no match" do
      with_server("", status_code: 404) do |base_url|
        client = LRCLIB::Client.new(base_url)

        client.get("Missing Artist", "Missing Track").should be_nil
      end
    end
  end
end

private def with_server(body : String, status_code : Int32 = 200, handler : Proc(HTTP::Server::Context, Nil)? = nil, &block : String ->)
  server = HTTP::Server.new do |context|
    handler.try &.call(context)
    context.response.status_code = status_code
    context.response.content_type = "application/json"
    context.response.print body
  end

  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }

  begin
    yield "http://127.0.0.1:#{address.port}"
  ensure
    server.close
  end
end
