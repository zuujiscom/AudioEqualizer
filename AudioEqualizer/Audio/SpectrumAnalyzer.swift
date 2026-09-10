import Foundation
import AVFoundation
import Accelerate

/// Reused across frames — the working buffers are allocated once so the
/// 20 Hz metering pass doesn't churn memory.
///
/// The window is 2,048 samples: at 48 kHz that is 23.4 Hz per FFT bin
/// (42.7 ms of audio) instead of 46.9 Hz, which is what lets the lowest
/// display bars resolve real bass instead of collapsing onto one bin.
/// `SystemAudioRenderer.analysisWindow` must match — a shorter ring buffer
/// would just zero-pad, which interpolates bins without adding resolution.
final class SpectrumAnalyzer {
    private let log2n: vDSP_Length
    private let n: Int
    private let fftSetup: FFTSetup
    private var window: [Float]
    private let binCount: Int = 64

    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    private var result: [Float]

    /// Display bar -> FFT bin range, rebuilt whenever the tap's sample rate
    /// changes. Linear bar spacing left the top ~10 bars sitting above 20 kHz,
    /// where no real source has energy, and crushed everything musical into
    /// the leftmost handful.
    private var binRanges: [(start: Int, end: Int)] = []
    private var binRangeSampleRate: Double = 0

    init() {
        log2n = vDSP_Length(log2(Float(2048)))
        n = Int(1 << log2n)
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        windowed = [Float](repeating: 0, count: n)
        realp = [Float](repeating: 0, count: n / 2)
        imagp = [Float](repeating: 0, count: n / 2)
        magnitudes = [Float](repeating: 0, count: n / 2)
        result = [Float](repeating: 0, count: binCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func analyze(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return result }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return result }

        rebuildBinRangesIfNeeded(sampleRate: buffer.format.sampleRate)
        guard binRanges.count == binCount else { return result }

        // Take up to one FFT window's worth; zero-pad anything shorter.
        let usable = min(frameCount, n)
        windowed.withUnsafeMutableBufferPointer { dest in
            guard let base = dest.baseAddress else { return }
            base.update(from: channelData[0], count: usable)
            if usable < n {
                (base + usable).update(repeating: 0, count: n - usable)
            }
        }
        vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(n))

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)

                windowed.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress?.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(n / 2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))

                for i in 0..<binCount {
                    let (start, end) = binRanges[i]
                    guard start < end else { continue }

                    var mean: Float = 0
                    magnitudes.withUnsafeBufferPointer { magPtr in
                        if let magBase = magPtr.baseAddress {
                            vDSP_meanv(magBase + start, 1, &mean, vDSP_Length(end - start))
                        }
                    }

                    // zrip returns squared magnitudes scaled by 2n.
                    let power = mean / Float(n * n)
                    let db = 10.0 * log10(max(1e-12, power))
                    let normalized = (db + 80) / 80   // map -80…0 dB to 0…1
                    result[i] = min(1, max(0, normalized))
                }
            }
        }

        return result
    }

    /// Spreads the display bars logarithmically over 20 Hz…20 kHz (or Nyquist,
    /// whichever is lower) so bass gets resolution and no bar maps above the
    /// audible band. With a 1,024-point FFT the lowest bars would all collapse
    /// onto the same FFT bin, so ranges are forced to advance by at least one
    /// bin while still leaving one bin for every remaining bar.
    private func rebuildBinRangesIfNeeded(sampleRate: Double) {
        guard sampleRate > 0, sampleRate != binRangeSampleRate else { return }
        binRangeSampleRate = sampleRate

        let halfCount = n / 2
        let binWidth = Float(sampleRate) / Float(n)
        let nyquist = Float(sampleRate) / 2
        let lowHz: Float = 20
        let highHz = min(Float(20_000), nyquist)

        func bin(for hz: Float) -> Int {
            Int((hz / binWidth).rounded())
        }

        var ranges: [(start: Int, end: Int)] = []
        ranges.reserveCapacity(binCount)

        let ratio = highHz / lowHz
        var previousStart = 0
        for i in 0..<binCount {
            let fLow = lowHz * powf(ratio, Float(i) / Float(binCount))
            let fHigh = lowHz * powf(ratio, Float(i + 1) / Float(binCount))

            // Skip DC, keep the ranges strictly increasing, and never consume
            // so many bins that a later bar has none left.
            let ceiling = halfCount - (binCount - i)
            var start = max(1, bin(for: fLow))
            start = max(start, previousStart + 1)
            start = min(start, ceiling)

            let end = min(halfCount, max(start + 1, bin(for: fHigh)))

            ranges.append((start, end))
            previousStart = start
        }

        binRanges = ranges
    }

    func rms(buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        vDSP_svesq(data[0], 1, &sum, vDSP_Length(count))
        return Double(sqrtf(sum / Float(count)))
    }
}
