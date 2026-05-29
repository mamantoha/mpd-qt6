module MPDUI
  class VisualizerService
    getter path : String

    @levels : Array(Float64)
    @mutex = Mutex.new
    @running = Atomic(Bool).new(false)

    def initialize(@path : String = ENV["MPD_VIS_FIFO"]? || "/tmp/mpd.fifo", @bar_count : Int32 = 48)
      @levels = Array.new(@bar_count, 0.0)
    end

    def start : Nil
      return if @running.swap(true)

      BackgroundRunner.run("mpd-ui-visualizer") { read_loop }
    end

    def stop : Nil
      @running.set(false)
    end

    def levels : Array(Float64)
      @mutex.synchronize { @levels.dup }
    end

    def reset : Nil
      @mutex.synchronize { @levels = Array.new(@bar_count, 0.0) }
    end

    private def read_loop : Nil
      frames_per_bar = 192
      bytes_per_frame = 4 # signed 16-bit little-endian stereo
      buffer = Bytes.new(@bar_count * frames_per_bar * bytes_per_frame)
      peak = 1.0

      while @running.get
        begin
          File.open(@path, "r") do |fifo|
            while @running.get
              bytes_read = read_full(fifo, buffer)
              break unless bytes_read == buffer.size

              frame_levels = decode_levels(buffer, bytes_read, frames_per_bar, bytes_per_frame)
              frame_peak = frame_levels.max? || 1.0
              peak = {frame_peak, peak * 0.92, 1.0}.max
              normalized = frame_levels.map { |level| (level / peak).clamp(0.0, 1.0) }

              @mutex.synchronize { @levels = normalized }
            end
          end
        rescue File::NotFoundError
          sleep 2.seconds
        rescue IO::Error
          sleep 500.milliseconds
        end
      end
    end

    private def read_full(io : IO, buffer : Bytes) : Int32
      bytes_read = 0

      while bytes_read < buffer.size && @running.get
        read = io.read(buffer[bytes_read, buffer.size - bytes_read])
        break if read == 0

        bytes_read += read
      end

      bytes_read
    end

    private def decode_levels(buffer : Bytes, bytes_read : Int32, frames_per_bar : Int32, bytes_per_frame : Int32) : Array(Float64)
      levels = [] of Float64
      offset = 0

      @bar_count.times do
        sum = 0.0
        count = 0

        frames_per_bar.times do
          break if offset + 3 >= bytes_read

          left = sample_i16_le(buffer[offset], buffer[offset + 1])
          right = sample_i16_le(buffer[offset + 2], buffer[offset + 3])
          mono = (left + right) / 2.0

          sum += mono.abs
          count += 1
          offset += bytes_per_frame
        end

        levels << (count > 0 ? sum / count : 0.0)
      end

      levels
    end

    private def sample_i16_le(low : UInt8, high : UInt8) : Int32
      value = low.to_i | (high.to_i << 8)
      value >= 32_768 ? value - 65_536 : value
    end
  end
end
