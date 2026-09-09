import Foundation
import AVFoundation
import Accelerate

/// Reused across frames — the working buffers are allocated once so the
/// 20 Hz metering pass doesn't churn memory.
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

    init() {
        log2n = vDSP_Length(log2(Float(1024)))
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

                let binSize = max(1, (n / 2) / binCount)
                for i in 0..<binCount {
                    let start = i * binSize
                    let end = min(start + binSize, n / 2)
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

    func rms(buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        vDSP_svesq(data[0], 1, &sum, vDSP_Length(count))
        return Double(sqrtf(sum / Float(count)))
    }
}
