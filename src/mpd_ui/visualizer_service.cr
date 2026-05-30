module MPDUI
  # Reads MPD's raw PCM FIFO output and turns it into normalized spectrum levels
  # for VisualizerWidget. MPD does not provide ready-to-draw visualizer data; it
  # only writes audio samples, so this class owns the FIFO loop and delegates the
  # DSP work to DSP::SpectrumAnalyzer.
  class VisualizerService
    # The highest recent band level is used as the current reference point.
    # This decay lets the reference fall between loud moments instead of pinning
    # the display to one old peak.
    PEAK_DECAY = 0.90

    # Release smoothing makes bars fall naturally instead of jittering every
    # frame. Rising bars are intentionally immediate.
    BAR_RELEASE = 0.58

    # Only this many dB below the current peak remain visible. A narrower range
    # gives a more lively music-player look; a wider range looks flatter.
    DYNAMIC_RANGE_DB = 36.0
    MIN_MAGNITUDE = 1e-12
    CONTRAST_POWER = 1.15

    @levels : Array(Float64)
    @mutex = Mutex.new
    @running = Atomic(Bool).new(false)
    @enabled = Atomic(Bool).new(true)
    @playback_active = Atomic(Bool).new(false)
    @connected = Atomic(Bool).new(false)
    @analyzer : DSP::SpectrumAnalyzer

    def initialize(@path : String = "/tmp/mpd.fifo", @bar_count : Int32 = 56)
      @levels = Array.new(@bar_count, 0.0)
      @analyzer = DSP::SpectrumAnalyzer.new(@bar_count)
    end

    def path : String
      @mutex.synchronize { @path }
    end

    def configure(enabled : Bool, path : String) : Nil
      @enabled.set(enabled)
      @connected.set(false)
      @mutex.synchronize do
        @path = path.empty? ? "/tmp/mpd.fifo" : path
        @levels = Array.new(@bar_count, 0.0) unless enabled
      end
    end

    def available? : Bool
      @enabled.get && (@connected.get || File.exists?(path))
    end

    def playback_active=(value : Bool) : Bool
      @playback_active.set(value)
      clear_levels unless value
      value
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
      @connected.set(false)
      clear_levels
    end

    def clear_levels : Nil
      @mutex.synchronize { @levels = Array.new(@bar_count, 0.0) }
    end

    private def read_loop : Nil
      bytes_per_frame = 4 # signed 16-bit little-endian stereo
      buffer = Bytes.new(DSP::SpectrumAnalyzer::FFT_SIZE * bytes_per_frame)
      peak = MIN_MAGNITUDE
      smoothing = Array.new(@bar_count, 0.0)

      while @running.get
        unless @enabled.get
          sleep 250.milliseconds
          next
        end

        unless @playback_active.get
          clear_levels
          sleep 250.milliseconds
          next
        end

        begin
          File.open(path, "r") do |fifo|
            while @running.get
              unless @enabled.get
                reset
                break
              end

              bytes_read = read_full(fifo, buffer)
              unless bytes_read == buffer.size
                break
              end

              unless @playback_active.get
                clear_levels
                break
              end

              frame_levels = @analyzer.levels(buffer, bytes_read, bytes_per_frame)

              # Normalize this frame against a slowly decaying peak so the
              # visualizer stays useful for both quiet and loud songs.
              frame_peak = frame_levels.max? || MIN_MAGNITUDE
              peak = {frame_peak, peak * PEAK_DECAY, MIN_MAGNITUDE}.max

              normalized = frame_levels.map_with_index do |level, index|
                value = spectrum_value(level, peak)
                previous = smoothing[index]
                smoothing[index] = value > previous ? value : previous * BAR_RELEASE + value * (1.0 - BAR_RELEASE)
              end

              @mutex.synchronize { @levels = normalized }
              @connected.set(true)
            end
          end
        rescue File::NotFoundError
          @connected.set(false)
          sleep 2.seconds
        rescue IO::Error
          @connected.set(false)
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

    private def spectrum_value(level : Float64, peak : Float64) : Float64
      return 0.0 unless level.positive? && peak.positive?

      # Convert relative magnitude to dB, then map the visible dB range to
      # 0.0..1.0 for painting. This makes weak bands fall away more naturally
      # than raw linear scaling.
      db = 20.0 * Math.log10({level / peak, MIN_MAGNITUDE}.max)
      value = ((db + DYNAMIC_RANGE_DB) / DYNAMIC_RANGE_DB).clamp(0.0, 1.0)
      value ** CONTRAST_POWER
    end

  end
end
