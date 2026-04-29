require "socket"
require "uri"

module MPDUI
  module MPRIS
    OBJECT     = "/org/mpris/MediaPlayer2"
    ROOT_IFACE = "org.mpris.MediaPlayer2"
    PLAYER     = "org.mpris.MediaPlayer2.Player"
    PROPERTIES = "org.freedesktop.DBus.Properties"
    INTROSPECT = "org.freedesktop.DBus.Introspectable"

    struct Options
      getter bus_name : String
      getter identity : String
      getter desktop_entry : String
      getter cache_prefix : String

      def initialize(app_id : String, @identity : String, @desktop_entry : String = app_id, @cache_prefix : String = app_id)
        @bus_name = "org.mpris.MediaPlayer2.#{dbus_name(app_id)}"
      end

      private def dbus_name(value : String) : String
        value.gsub(/[^A-Za-z0-9_]/, "_")
      end
    end

    struct State
      property playback_status : String = "Stopped"
      property title : String = ""
      property artist : String = ""
      property album : String = ""
      property file : String = ""
      property art_url : String = ""
      property track_id : Int32? = nil
      property length_us : Int64 = 0_i64
      property position_us : Int64 = 0_i64
      property volume : Float64 = 1.0
      property shuffle : Bool = false
      property repeat : Bool = false
    end

    alias Command = Proc(Nil)
    alias SeekCommand = Proc(Int64, Nil)
    alias VolumeCommand = Proc(Float64, Nil)
    alias PositionCommand = Proc(String, Int64, Nil)

    class Service
      property on_raise : Command?
      property on_quit : Command?
      property on_play : Command?
      property on_pause : Command?
      property on_play_pause : Command?
      property on_stop : Command?
      property on_next : Command?
      property on_previous : Command?
      property on_seek : SeekCommand?
      property on_set_volume : VolumeCommand?
      property on_set_position : PositionCommand?

      @socket : UNIXSocket?
      @serial = 1_u32
      @running = Atomic(Bool).new(false)
      @mutex = Mutex.new
      @state = State.new

      getter options : Options

      def initialize(@options : Options)
      end

      def start : Nil
        return if @running.get

        @running.set(true)
        Thread.new do
          run
        rescue ex
          Log.warn { "mpris: #{ex.message || ex}" }
          @running.set(false)
        end
      end

      def stop : Nil
        @running.set(false)
      end

      def update_state(state : State) : Nil
        return unless @running.get

        @mutex.synchronize { @state = state }
        emit_player_properties_changed
      rescue ex
        Log.debug { "mpris: failed to emit state change: #{ex.message || ex}" }
      end

      # Opens the session bus, publishes this service as an MPRIS player, and
      # keeps listening for desktop media-control requests.
      private def run : Nil
        address = ENV["DBUS_SESSION_BUS_ADDRESS"]?
        unless address
          Log.info { "mpris: DBUS_SESSION_BUS_ADDRESS is not set" }
          return
        end

        socket = connect_session_bus(address)
        @socket = socket
        authenticate(socket)
        hello
        request_name

        while @running.get
          message = Message.read(socket)
          handle(message) if message
        end
      ensure
        @socket.try(&.close)
        @socket = nil
      end

      # Opens the Unix socket for the user's DBus session bus. MPRIS is a
      # session-bus protocol because it is consumed by the logged-in desktop.
      private def connect_session_bus(address : String) : UNIXSocket
        parts = address.split(';').find(&.starts_with?("unix:")) || address
        values = {} of String => String
        parts.sub(/^unix:/, "").split(',').each do |part|
          key, value = part.split('=', 2)
          values[key] = URI.decode_www_form(value || "")
        end

        if path = values["path"]?
          UNIXSocket.new(path)
        else
          raise "only DBus unix:path session bus addresses are supported"
        end
      end

      # Proves this process identity to the DBus daemon so the socket can switch
      # from text authentication commands to normal binary DBus messages.
      private def authenticate(socket : UNIXSocket) : Nil
        # DBus starts with a small SASL-style authentication exchange before
        # binary messages are allowed. EXTERNAL uses the current Unix uid,
        # encoded as hex ASCII, after an initial NUL byte.
        uid = LibC.getuid.to_s
        hex_uid = uid.bytes.map { |byte| byte.to_s(16).rjust(2, '0') }.join
        socket.write_byte(0_u8)
        socket << "AUTH EXTERNAL #{hex_uid}\r\n"
        line = socket.gets("\r\n") || ""
        raise "DBus auth failed: #{line.strip}" unless line.starts_with?("OK")
        socket << "BEGIN\r\n"
        socket.flush
      end

      private def next_serial : UInt32
        serial = @serial
        @serial += 1
        serial
      end

      # Sends one DBus message to the bus. Replies, signals, and bus method
      # calls all use this path so framing stays consistent.
      private def send_message(type : UInt8, flags : UInt8, fields : Array(HeaderField), body : Bytes = Bytes.empty, signature : String? = nil) : UInt32
        socket = @socket
        return 0_u32 unless socket

        # All outgoing DBus messages pass through here. The serial lets peers
        # match replies to calls; field 8 carries the optional body signature.
        serial = next_serial
        all_fields = fields.dup
        all_fields << HeaderField.new(8_u8, BasicValue.signature(signature)) if signature && !signature.empty?
        message = Message.build(type, flags, serial, all_fields, body)
        socket.write(message)
        socket.flush
        serial
      end

      # Sends a DBus method call. This is used for calls to the bus daemon
      # itself, such as Hello and RequestName.
      private def call(destination : String, path : String, interface : String, member : String, body : Bytes = Bytes.empty, signature : String? = nil) : UInt32
        # A DBus method call is just a message with routing fields:
        # object path, interface, member name, and destination bus name.
        send_message(1_u8, 0_u8, [
          HeaderField.new(1_u8, BasicValue.object_path(path)),
          HeaderField.new(2_u8, BasicValue.string(interface)),
          HeaderField.new(3_u8, BasicValue.string(member)),
          HeaderField.new(6_u8, BasicValue.string(destination)),
        ], body, signature)
      end

      # Registers this socket as a DBus client. Without Hello, the bus has not
      # assigned us a unique name and later operations are not valid.
      private def hello : Nil
        # Hello registers this connection with the bus and assigns a unique
        # name. We wait for its reply before requesting the public MPRIS name.
        call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello")
        loop do
          message = Message.read(@socket.not_nil!)
          break if message && message.type == 2_u8
        end
      end

      # Claims the public MPRIS player name so desktop shells and tools like
      # playerctl can discover this process as a media player.
      private def request_name : Nil
        # Desktop media controls discover players by this well-known name:
        # org.mpris.MediaPlayer2.<app_id>.
        body = Writer.build do |w|
          w.write_string(@options.bus_name)
          w.write_u32(0_u32)
        end
        call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", body, "su")
      end

      # Routes incoming method calls to the small set of interfaces this service
      # exports: introspection, generic properties, and the two MPRIS interfaces.
      private def handle(message : Message) : Nil
        return unless message.type == 1_u8
        return unless message.path == OBJECT

        case message.interface
        when INTROSPECT
          reply(message, Writer.build { |w| w.write_string(introspection_xml) }, "s") if message.member == "Introspect"
        when PROPERTIES
          handle_properties(message)
        when ROOT_IFACE
          handle_root(message)
        when PLAYER
          handle_player(message)
        end
      rescue ex
        Log.debug { "mpris: failed to handle #{message.interface}.#{message.member}: #{ex.message || ex}" }
      end

      # Implements org.freedesktop.DBus.Properties so clients can read MPRIS
      # state and set writable properties such as Volume.
      private def handle_properties(message : Message) : Nil
        reader = Reader.new(message.body, message.signature)
        case message.member
        when "Get"
          iface = reader.read_string
          property = reader.read_string
          reply(message, Writer.build { |w| write_property_variant(w, iface, property) }, "v")
        when "GetAll"
          iface = reader.read_string
          reply(message, Writer.build { |w| write_properties(w, iface) }, "a{sv}")
        when "Set"
          iface = reader.read_string
          property = reader.read_string
          if iface == PLAYER && property == "Volume"
            volume = reader.read_variant_double
            @on_set_volume.try(&.call(volume))
          end
          reply(message)
        end
      end

      # Handles application-level MPRIS requests that are not playback-specific.
      private def handle_root(message : Message) : Nil
        case message.member
        when "Raise"
          @on_raise.try(&.call)
          reply(message)
        when "Quit"
          @on_quit.try(&.call)
          reply(message)
        end
      end

      # Handles playback-control requests from desktop media keys, shell
      # controls, lock screens, and tools like playerctl.
      private def handle_player(message : Message) : Nil
        reader = Reader.new(message.body, message.signature)
        case message.member
        when "Next"
          @on_next.try(&.call)
        when "Previous"
          @on_previous.try(&.call)
        when "Pause"
          @on_pause.try(&.call)
        when "PlayPause"
          @on_play_pause.try(&.call)
        when "Stop"
          @on_stop.try(&.call)
        when "Play"
          @on_play.try(&.call)
        when "Seek"
          @on_seek.try(&.call(reader.read_i64))
        when "SetPosition"
          @on_set_position.try(&.call(reader.read_object_path, reader.read_i64))
        end
        reply(message)
      end

      # Sends a DBus method return for a handled call. The reply serial points
      # back to the caller's message serial.
      private def reply(message : Message, body : Bytes = Bytes.empty, signature : String? = nil) : Nil
        fields = [
          HeaderField.new(5_u8, BasicValue.uint32(message.serial)),
        ]
        if sender = message.sender
          fields << HeaderField.new(6_u8, BasicValue.string(sender))
        end
        send_message(2_u8, 1_u8, fields, body, signature)
      end

      # Notifies clients that playback state, metadata, position, or volume has
      # changed so they can refresh their UI without polling.
      private def emit_player_properties_changed : Nil
        body = Writer.build do |w|
          w.write_string(PLAYER)
          write_properties(w, PLAYER)
          w.write_array("s") { |_aw| }
        end

        send_message(4_u8, 1_u8, [
          HeaderField.new(1_u8, BasicValue.object_path(OBJECT)),
          HeaderField.new(2_u8, BasicValue.string(PROPERTIES)),
          HeaderField.new(3_u8, BasicValue.string("PropertiesChanged")),
        ], body, "sa{sv}as")
      end

      # Serializes all properties for one exported interface in the a{sv} shape
      # required by org.freedesktop.DBus.Properties.GetAll.
      private def write_properties(w : Writer, iface : String) : Nil
        entries = [] of Tuple(String, Proc(Writer, Nil))

        if iface == ROOT_IFACE
          entries = root_properties
        elsif iface == PLAYER
          entries = player_properties
        end

        w.write_array("{sv}") do |aw|
          entries.each do |name, writer|
            aw.align(8)
            aw.write_string(name)
            writer.call(aw)
          end
        end
      end

      # Serializes one property as a variant for
      # org.freedesktop.DBus.Properties.Get.
      private def write_property_variant(w : Writer, iface : String, property : String) : Nil
        properties = iface == ROOT_IFACE ? root_properties : player_properties
        entry = properties.find { |name, _| name == property }
        if entry
          entry[1].call(w)
        else
          w.write_variant("s") { |vw| vw.write_string("") }
        end
      end

      private def root_properties
        [
          {"CanQuit", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(true) } }},
          {"CanRaise", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(true) } }},
          {"HasTrackList", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(false) } }},
          {"Identity", ->(w : Writer) { w.write_variant("s") { |vw| vw.write_string(@options.identity) } }},
          {"DesktopEntry", ->(w : Writer) { w.write_variant("s") { |vw| vw.write_string(@options.desktop_entry) } }},
          {"SupportedUriSchemes", ->(w : Writer) { w.write_variant("as") { |vw| vw.write_array("s") { |aw| aw.write_string("file") } } }},
          {"SupportedMimeTypes", ->(w : Writer) { w.write_variant("as") { |vw| vw.write_array("s") { |_aw| } } }},
        ]
      end

      private def player_properties
        state = @mutex.synchronize { @state }
        [
          {"PlaybackStatus", ->(w : Writer) { w.write_variant("s") { |vw| vw.write_string(state.playback_status) } }},
          {"LoopStatus", ->(w : Writer) { w.write_variant("s") { |vw| vw.write_string(state.repeat ? "Playlist" : "None") } }},
          {"Rate", ->(w : Writer) { w.write_variant("d") { |vw| vw.write_f64(1.0) } }},
          {"Shuffle", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(state.shuffle) } }},
          {"Metadata", ->(w : Writer) { w.write_variant("a{sv}") { |vw| write_metadata(vw, state) } }},
          {"Volume", ->(w : Writer) { w.write_variant("d") { |vw| vw.write_f64(state.volume) } }},
          {"Position", ->(w : Writer) { w.write_variant("x") { |vw| vw.write_i64(state.position_us) } }},
          {"MinimumRate", ->(w : Writer) { w.write_variant("d") { |vw| vw.write_f64(1.0) } }},
          {"MaximumRate", ->(w : Writer) { w.write_variant("d") { |vw| vw.write_f64(1.0) } }},
          {"CanGoNext", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(true) } }},
          {"CanGoPrevious", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(true) } }},
          {"CanPlay", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(true) } }},
          {"CanPause", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(true) } }},
          {"CanSeek", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(state.length_us > 0) } }},
          {"CanControl", ->(w : Writer) { w.write_variant("b") { |vw| vw.write_bool(true) } }},
        ]
      end

      # Converts the current song into MPRIS/Xesam metadata keys understood by
      # desktop shells, notifications, and media widgets.
      private def write_metadata(w : Writer, state : State) : Nil
        w.write_array("{sv}") do |aw|
          write_dict_variant(aw, "mpris:trackid", "o") { |vw| vw.write_object_path(track_path(state.track_id)) }
          write_dict_variant(aw, "mpris:length", "x") { |vw| vw.write_i64(state.length_us) } if state.length_us > 0
          write_dict_variant(aw, "xesam:title", "s") { |vw| vw.write_string(state.title) } unless state.title.empty?
          write_dict_variant(aw, "xesam:artist", "as") { |vw| vw.write_array("s") { |arr| arr.write_string(state.artist) } } unless state.artist.empty?
          write_dict_variant(aw, "xesam:album", "s") { |vw| vw.write_string(state.album) } unless state.album.empty?
          write_dict_variant(aw, "xesam:url", "s") { |vw| vw.write_string(file_url(state.file)) } unless state.file.empty?
          write_dict_variant(aw, "mpris:artUrl", "s") { |vw| vw.write_string(state.art_url) } unless state.art_url.empty?
        end
      end

      private def write_dict_variant(w : Writer, key : String, signature : String, & : Writer -> Nil) : Nil
        w.align(8)
        w.write_string(key)
        w.write_variant(signature) { |vw| yield vw }
      end

      # Returns a stable object path for the current track, as required by the
      # MPRIS metadata format.
      private def track_path(id : Int32?) : String
        "#{OBJECT}/Track/#{id || 0}"
      end

      # Converts local paths to file URLs because MPRIS metadata URLs must be
      # URI strings, not raw filesystem paths.
      private def file_url(file : String) : String
        file.starts_with?("/") ? "file://#{URI.encode_path(file)}" : file
      end

      # Describes the exported object for clients that inspect DBus services at
      # runtime instead of relying only on the MPRIS spec.
      private def introspection_xml : String
        <<-XML
        <!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
         "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
        <node>
          <interface name="org.freedesktop.DBus.Introspectable">
            <method name="Introspect"><arg name="xml" type="s" direction="out"/></method>
          </interface>
          <interface name="org.freedesktop.DBus.Properties">
            <method name="Get"><arg name="interface" type="s" direction="in"/><arg name="property" type="s" direction="in"/><arg name="value" type="v" direction="out"/></method>
            <method name="GetAll"><arg name="interface" type="s" direction="in"/><arg name="properties" type="a{sv}" direction="out"/></method>
            <method name="Set"><arg name="interface" type="s" direction="in"/><arg name="property" type="s" direction="in"/><arg name="value" type="v" direction="in"/></method>
            <signal name="PropertiesChanged"><arg name="interface" type="s"/><arg name="changed_properties" type="a{sv}"/><arg name="invalidated_properties" type="as"/></signal>
          </interface>
          <interface name="org.mpris.MediaPlayer2">
            <method name="Raise"/><method name="Quit"/>
          </interface>
          <interface name="org.mpris.MediaPlayer2.Player">
            <method name="Next"/><method name="Previous"/><method name="Pause"/><method name="PlayPause"/><method name="Stop"/><method name="Play"/>
            <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
            <method name="SetPosition"><arg name="TrackId" type="o" direction="in"/><arg name="Position" type="x" direction="in"/></method>
            <method name="OpenUri"><arg name="Uri" type="s" direction="in"/></method>
          </interface>
        </node>
        XML
      end
    end

    struct BasicValue
      getter signature : String
      getter value : String | UInt32

      def initialize(@signature : String, @value : String | UInt32)
      end

      def self.string(value : String) : self
        new("s", value)
      end

      def self.object_path(value : String) : self
        new("o", value)
      end

      def self.signature(value : String) : self
        new("g", value)
      end

      def self.uint32(value : UInt32) : self
        new("u", value)
      end

      def write(w : Writer) : Nil
        case @signature
        when "s"
          w.write_string(@value.as(String))
        when "o"
          w.write_object_path(@value.as(String))
        when "g"
          w.write_signature(@value.as(String))
        when "u"
          w.write_u32(@value.as(UInt32))
        end
      end
    end

    struct HeaderField
      getter code : UInt8
      getter value : BasicValue

      def initialize(@code : UInt8, @value : BasicValue)
      end
    end

    class Message
      getter type : UInt8
      getter serial : UInt32
      getter path : String?
      getter interface : String?
      getter member : String?
      getter sender : String?
      getter signature : String
      getter body : Bytes

      def initialize(@type : UInt8, @serial : UInt32, @path : String?, @interface : String?, @member : String?, @sender : String?, @signature : String, @body : Bytes)
      end

      # Reads one raw DBus frame from the socket and extracts the fields needed
      # to route it to the correct service handler.
      def self.read(io : IO) : self?
        # DBus messages have a fixed 16-byte header, a variable header field
        # block, padding to the next 8-byte boundary, then the body bytes.
        fixed = Bytes.new(16)
        io.read_fully(fixed)
        raise "unsupported DBus endian" unless fixed[0] == 'l'.ord

        type = fixed[1]
        body_len = IO::ByteFormat::LittleEndian.decode(UInt32, fixed[4, 4])
        serial = IO::ByteFormat::LittleEndian.decode(UInt32, fixed[8, 4])
        header_len = IO::ByteFormat::LittleEndian.decode(UInt32, fixed[12, 4])

        header = Bytes.new(header_len)
        io.read_fully(header)
        pad_len = (8 - ((16 + header_len) % 8)) % 8
        io.skip(pad_len) if pad_len > 0

        body = Bytes.new(body_len)
        io.read_fully(body) if body_len > 0

        reader = Reader.new(header, "a(yv)")
        path = interface = member = sender = nil
        signature = ""
        reader.each_header_field do |code, value_signature, value|
          case code
          when 1
            path = value if value_signature == "o"
          when 2
            interface = value if value_signature == "s"
          when 3
            member = value if value_signature == "s"
          when 7
            sender = value if value_signature == "s"
          when 8
            signature = value if value_signature == "g"
          end
        end

        new(type, serial, path, interface, member, sender, signature, body)
      rescue IO::EOFError
        nil
      end

      # Builds a raw DBus frame from structured header fields and body bytes so
      # it can be written directly to the session bus socket.
      def self.build(type : UInt8, flags : UInt8, serial : UInt32, fields : Array(HeaderField), body : Bytes) : Bytes
        # Build the inverse of read: serialize header fields, then wrap them
        # with the fixed DBus header and required padding before the body.
        header = Writer.build do |w|
          fields.each do |field|
            w.align(8)
            w.write_u8(field.code)
            w.write_variant(field.value.signature) { |vw| field.value.write(vw) }
          end
        end

        IO::Memory.new.tap do |io|
          io.write_byte('l'.ord.to_u8)
          io.write_byte(type)
          io.write_byte(flags)
          io.write_byte(1_u8)
          io.write_bytes(body.size.to_u32, IO::ByteFormat::LittleEndian)
          io.write_bytes(serial, IO::ByteFormat::LittleEndian)
          io.write_bytes(header.size.to_u32, IO::ByteFormat::LittleEndian)
          io.write(header)
          ((8 - io.pos % 8) % 8).times { io.write_byte(0_u8) }
          io.write(body)
        end.to_slice
      end
    end

    class Reader
      def initialize(@bytes : Bytes, @signature : String)
        @offset = 0
      end

      # Decodes the message header field block so Message.read can find routing
      # information such as path, interface, member, sender, and body signature.
      def each_header_field(& : UInt8, String, String -> Nil) : Nil
        # Header fields are structs: a numeric field code plus a variant value.
        # We decode only the simple field types needed for routing this service.
        end_offset = @bytes.size
        while @offset < end_offset
          align(8)
          code = read_u8
          value_signature, value = read_simple_variant
          yield code, value_signature, value
        end
      end

      def read_string : String
        align(4)
        len = read_u32.to_i
        value = String.new(@bytes[@offset, len])
        @offset += len + 1
        value
      end

      def read_object_path : String
        read_string
      end

      def read_i64 : Int64
        align(8)
        value = IO::ByteFormat::LittleEndian.decode(Int64, @bytes[@offset, 8])
        @offset += 8
        value
      end

      def read_variant_double : Float64
        signature = read_signature
        align_for(signature)
        case signature
        when "d"
          read_f64
        when "i"
          read_i32.to_f
        when "u"
          read_u32.to_f
        else
          0.0
        end
      end

      private def read_simple_variant : Tuple(String, String)
        signature = read_signature
        align_for(signature)
        value = case signature
                when "s", "o"
                  read_string
                when "g"
                  read_signature
                when "u"
                  read_u32.to_s
                else
                  ""
                end
        {signature, value}
      end

      private def read_signature : String
        len = read_u8.to_i
        value = String.new(@bytes[@offset, len])
        @offset += len + 1
        value
      end

      private def read_u8 : UInt8
        value = @bytes[@offset]
        @offset += 1
        value
      end

      private def read_u32 : UInt32
        align(4)
        value = IO::ByteFormat::LittleEndian.decode(UInt32, @bytes[@offset, 4])
        @offset += 4
        value
      end

      private def read_i32 : Int32
        align(4)
        value = IO::ByteFormat::LittleEndian.decode(Int32, @bytes[@offset, 4])
        @offset += 4
        value
      end

      private def read_f64 : Float64
        align(8)
        value = IO::ByteFormat::LittleEndian.decode(Float64, @bytes[@offset, 8])
        @offset += 8
        value
      end

      private def align_for(signature : String) : Nil
        align(signature == "x" || signature == "t" || signature == "d" || signature.starts_with?("(") || signature.starts_with?("{") ? 8 : signature == "s" || signature == "o" || signature == "u" || signature == "i" || signature.starts_with?("a") ? 4 : 1)
      end

      private def align(boundary : Int32) : Nil
        # DBus values must start on type-specific byte boundaries. If alignment
        # is wrong, every following value in the message is read incorrectly.
        remainder = @offset % boundary
        @offset += boundary - remainder unless remainder == 0
      end
    end

    class Writer
      def self.build(& : Writer -> Nil) : Bytes
        writer = new
        yield writer
        writer.to_slice
      end

      def initialize
        @io = IO::Memory.new
      end

      def to_slice : Bytes
        @io.to_slice
      end

      def pos : Int32
        @io.pos.to_i
      end

      # Moves the write cursor to a DBus alignment boundary before writing the
      # next value.
      def align(boundary : Int32) : Nil
        # DBus values must start on type-specific byte boundaries. Padding bytes
        # are not part of the value; they only move the write cursor forward.
        remainder = @io.pos % boundary
        (boundary - remainder).times { @io.write_byte(0_u8) } unless remainder == 0
      end

      def write_u8(value : UInt8) : Nil
        @io.write_byte(value)
      end

      def write_bool(value : Bool) : Nil
        write_u32(value ? 1_u32 : 0_u32)
      end

      def write_u32(value : UInt32) : Nil
        align(4)
        @io.write_bytes(value, IO::ByteFormat::LittleEndian)
      end

      def write_i64(value : Int64) : Nil
        align(8)
        @io.write_bytes(value, IO::ByteFormat::LittleEndian)
      end

      def write_f64(value : Float64) : Nil
        align(8)
        @io.write_bytes(value, IO::ByteFormat::LittleEndian)
      end

      def write_string(value : String) : Nil
        align(4)
        @io.write_bytes(value.bytesize.to_u32, IO::ByteFormat::LittleEndian)
        @io.write(value.to_slice)
        @io.write_byte(0_u8)
      end

      def write_object_path(value : String) : Nil
        write_string(value)
      end

      def write_signature(value : String) : Nil
        @io.write_byte(value.bytesize.to_u8)
        @io.write(value.to_slice)
        @io.write_byte(0_u8)
      end

      # Writes a DBus variant, used heavily by properties because DBus property
      # values are typed dynamically.
      def write_variant(signature : String, & : Writer -> Nil) : Nil
        # A DBus variant stores its own signature first, followed by the value
        # aligned as if it had appeared directly in the message.
        write_signature(signature)
        align_for(signature)
        yield self
      end

      # Writes a DBus array, used for dictionaries such as a{sv} property maps
      # and metadata maps.
      def write_array(element_signature : String, & : Writer -> Nil) : Nil
        # DBus arrays are length-prefixed byte blocks. Reserve the length,
        # write the aligned contents, then patch the byte count afterward.
        align(4)
        length_pos = @io.pos
        write_u32(0_u32)
        align_for(element_signature)
        start_pos = @io.pos
        yield self
        end_pos = @io.pos
        slice = @io.to_slice
        IO::ByteFormat::LittleEndian.encode((end_pos - start_pos).to_u32, slice[length_pos, 4])
      end

      private def align_for(signature : String) : Nil
        align(signature == "x" || signature == "t" || signature == "d" || signature.starts_with?("(") || signature.starts_with?("{") ? 8 : signature == "s" || signature == "o" || signature == "u" || signature == "i" || signature.starts_with?("a") ? 4 : 1)
      end
    end
  end
end
