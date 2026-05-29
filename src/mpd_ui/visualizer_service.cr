module MPDUI
  # Reads MPD's raw PCM FIFO output and turns it into normalized spectrum levels
  # for VisualizerWidget. MPD does not provide ready-to-draw visualizer data; it
  # only writes audio samples, so this class performs the small DSP pipeline:
  #
  #   PCM bytes -> mono samples -> windowed FFT -> frequency bands -> UI levels
  #
  # The result is intentionally tuned for a music-player visualizer, not for
  # scientific measurement. Constants below control how responsive and contrasted
  # the bars feel on screen.
  class VisualizerService
    # 2048 samples gives enough low-frequency resolution for bass bars while
    # still reacting quickly enough for a compact player header visualizer.
    FFT_SIZE = 2048
    SAMPLE_RATE = 44_100.0

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
    @available = Atomic(Bool).new(false)

    def initialize(@path : String = "/tmp/mpd.fifo", @bar_count : Int32 = 56)
      @levels = Array.new(@bar_count, 0.0)
    end

    def path : String
      @mutex.synchronize { @path }
    end

    def configure(enabled : Bool, path : String) : Nil
      @enabled.set(enabled)
      @available.set(false)
      @mutex.synchronize do
        @path = path.empty? ? "/tmp/mpd.fifo" : path
        @levels = Array.new(@bar_count, 0.0) unless enabled
      end
    end

    def available? : Bool
      @available.get
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
      @available.set(false)
      @mutex.synchronize { @levels = Array.new(@bar_count, 0.0) }
    end

    private def read_loop : Nil
      bytes_per_frame = 4 # signed 16-bit little-endian stereo
      buffer = Bytes.new(FFT_SIZE * bytes_per_frame)
      peak = MIN_MAGNITUDE
      smoothing = Array.new(@bar_count, 0.0)

      while @running.get
        unless @enabled.get
          @available.set(false)
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
                @available.set(false)
                break
              end

              samples = decode_spectrum_samples(buffer, bytes_read, bytes_per_frame)
              frame_levels = spectrum_levels(samples)

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
              @available.set(true)
            end
          end
        rescue File::NotFoundError
          @available.set(false)
          sleep 2.seconds
        rescue IO::Error
          @available.set(false)
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

    private def decode_spectrum_samples(buffer : Bytes, bytes_read : Int32, bytes_per_frame : Int32) : Array(Float64)
      samples = Array.new(FFT_SIZE, 0.0)
      offset = 0
      index = 0

      while index < FFT_SIZE && offset + 3 < bytes_read
        left = sample_i16_le(buffer[offset], buffer[offset + 1])
        right = sample_i16_le(buffer[offset + 2], buffer[offset + 3])

        # MPD writes stereo samples. The header visualizer is mono, so we mix
        # both channels and scale signed 16-bit PCM into roughly -1.0..1.0.
        mono = (left + right) / 65_536.0

        # The Hann window reduces spectral leakage: without it, the FFT would
        # smear one tone across many neighboring bars.
        window = 0.5 * (1.0 - Math.cos(2.0 * Math::PI * index / (FFT_SIZE - 1)))

        samples[index] = mono * window
        index += 1
        offset += bytes_per_frame
      end

      samples
    end

    private def spectrum_levels(samples : Array(Float64)) : Array(Float64)
      real = samples.dup
      imag = Array.new(samples.size, 0.0)

      # Convert the time-domain waveform into frequency magnitudes.
      fft(real, imag)

      min_bin = 2
      max_bin = samples.size // 2 - 1
      min_freq = 50.0
      max_freq = 16_000.0
      bin_edges = spectrum_bin_edges(min_freq, max_freq, min_bin, max_bin)

      Array.new(@bar_count) do |bar|
        low_bin = bin_edges[bar]
        high_bin = bin_edges[bar + 1]
        center_freq = (low_bin + high_bin) * 0.5 * SAMPLE_RATE / FFT_SIZE

        power = 0.0
        count = 0

        (low_bin...high_bin).each do |bin|
          power += real[bin] * real[bin] + imag[bin] * imag[bin]
          count += 1
        end

        # RMS energy per band is more stable than a single-bin peak. The small
        # frequency weighting is subjective: it gives bass/lower mids enough
        # visual presence for a compact horizontal display.
        count > 0 ? Math.sqrt(power / count) * frequency_weight(center_freq) : 0.0
      end
    end

    private def frequency_bin(frequency : Float64) : Int32
      (frequency * FFT_SIZE / SAMPLE_RATE).round.to_i
    end

    private def spectrum_bin_edges(min_freq : Float64, max_freq : Float64, min_bin : Int32, max_bin : Int32) : Array(Int32)
      min_log = Math.log10(min_freq)
      max_log = Math.log10(max_freq)

      # Human hearing is closer to logarithmic than linear, so low frequencies
      # get more visual space. The monotonic pass below prevents adjacent bars
      # from accidentally sharing the same FFT bin at the low end.
      edges = Array.new(@bar_count + 1) do |index|
        frequency = 10.0 ** (min_log + (max_log - min_log) * index / @bar_count)
        frequency_bin(frequency).clamp(min_bin, max_bin + 1)
      end

      (1...edges.size).each do |index|
        edges[index] = {edges[index], edges[index - 1] + 1}.max
      end

      edges.map { |edge| edge.clamp(min_bin, max_bin + 1) }
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

    private def frequency_weight(frequency : Float64) : Float64
      case
      when frequency <= 100.0
        1.30
      when frequency <= 250.0
        1.18
      when frequency <= 2_000.0
        1.0
      when frequency <= 6_000.0
        0.92
      else
        0.82
      end
    end

    private def fft(real : Array(Float64), imag : Array(Float64)) : Nil
      size = real.size
      j = 0

      # In-place radix-2 Cooley-Tukey FFT. This keeps the visualizer dependency
      # free; if we later need more precision or speed, this method is the one
      # to replace with FFTW or another DSP implementation.
      (1...size).each do |i|
        bit = size >> 1
        while (j & bit) != 0
          j ^= bit
          bit >>= 1
        end
        j ^= bit

        next unless i < j

        real[i], real[j] = real[j], real[i]
        imag[i], imag[j] = imag[j], imag[i]
      end

      length = 2
      while length <= size
        angle = -2.0 * Math::PI / length
        w_len_real = Math.cos(angle)
        w_len_imag = Math.sin(angle)
        half = length // 2

        i = 0
        while i < size
          w_real = 1.0
          w_imag = 0.0

          half.times do |offset|
            even = i + offset
            odd = even + half
            odd_real = real[odd] * w_real - imag[odd] * w_imag
            odd_imag = real[odd] * w_imag + imag[odd] * w_real

            real[odd] = real[even] - odd_real
            imag[odd] = imag[even] - odd_imag
            real[even] += odd_real
            imag[even] += odd_imag

            next_w_real = w_real * w_len_real - w_imag * w_len_imag
            w_imag = w_real * w_len_imag + w_imag * w_len_real
            w_real = next_w_real
          end

          i += length
        end

        length <<= 1
      end
    end

    private def sample_i16_le(low : UInt8, high : UInt8) : Int32
      value = low.to_i | (high.to_i << 8)
      value >= 32_768 ? value - 65_536 : value
    end
  end
end
