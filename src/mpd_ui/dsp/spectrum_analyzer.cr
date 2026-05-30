module MPDUI
  module DSP
    class SpectrumAnalyzer
      # 2048 samples gives enough low-frequency resolution for bass bars while
      # still reacting quickly enough for a compact player header visualizer.
      FFT_SIZE = 2048
      SAMPLE_RATE = 44_100.0

      def initialize(@bar_count : Int32)
      end

      def levels(buffer : Bytes, bytes_read : Int32, bytes_per_frame : Int32) : Array(Float64)
        samples = decode_samples(buffer, bytes_read, bytes_per_frame)
        spectrum_levels(samples)
      end

      private def decode_samples(buffer : Bytes, bytes_read : Int32, bytes_per_frame : Int32) : Array(Float64)
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
end
