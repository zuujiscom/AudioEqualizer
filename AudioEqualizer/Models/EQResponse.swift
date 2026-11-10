// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The combined frequency response of a set of bands, for drawing the EQ
/// curve. This is a model of what `AVAudioUnitEQ` does, built from the
/// standard audio-EQ-cookbook biquads — it is for display only and is never
/// in the audio path, so a small mismatch with Apple's filters costs nothing
/// but a pixel.
enum EQResponse {
    /// One second-order section, normalised so `a0` is 1.
    struct Biquad {
        var b0, b1, b2, a1, a2: Double

        /// Gain in dB at angular frequency `w` (radians per sample).
        func decibels(at w: Double) -> Double {
            let c1 = cos(w)
            let c2 = cos(2 * w)
            let numerator = b0 * b0 + b1 * b1 + b2 * b2 + 2 * (b0 * b1 + b1 * b2) * c1 + 2 * b0 * b2 * c2
            let denominator = 1 + a1 * a1 + a2 * a2 + 2 * (a1 + a1 * a2) * c1 + 2 * a2 * c2
            guard numerator > 0, denominator > 0 else { return -60 }
            return 10 * log10(numerator / denominator)
        }
    }

    /// Sections for every enabled band. Disabled bands are skipped, exactly as
    /// the engine bypasses them.
    static func sections(for bands: [EQBand], sampleRate: Double = 48_000) -> [Biquad] {
        bands.compactMap { band in
            band.isEnabled ? section(for: band, sampleRate: sampleRate) : nil
        }
    }

    static func decibels(_ sections: [Biquad], at frequency: Double, sampleRate: Double = 48_000) -> Double {
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.499) / sampleRate
        return sections.reduce(0) { $0 + $1.decibels(at: w) }
    }

    private static func section(for band: EQBand, sampleRate: Double) -> Biquad? {
        let frequency = min(max(band.frequency, 10), sampleRate * 0.49)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w0)
        let sinW = sin(w0)
        let a = pow(10, band.gain / 40)
        let bandwidth = min(max(band.bandwidth, 0.05), 5)
        // Bandwidth in octaves, the unit AVAudioUnitEQ uses.
        let alphaBW = sinW * sinh(log(2) / 2 * bandwidth * w0 / max(sinW, 1e-9))
        let alphaQ = sinW / (2 * 0.7071)

        var b0, b1, b2, a0, a1, a2: Double
        switch band.filterType {
        case .parametric:
            guard band.gain != 0 else { return nil }
            b0 = 1 + alphaBW * a; b1 = -2 * cosW; b2 = 1 - alphaBW * a
            a0 = 1 + alphaBW / a; a1 = -2 * cosW; a2 = 1 - alphaBW / a
        case .lowShelf:
            guard band.gain != 0 else { return nil }
            let k = 2 * sqrt(a) * alphaQ
            b0 = a * ((a + 1) - (a - 1) * cosW + k)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosW)
            b2 = a * ((a + 1) - (a - 1) * cosW - k)
            a0 = (a + 1) + (a - 1) * cosW + k
            a1 = -2 * ((a - 1) + (a + 1) * cosW)
            a2 = (a + 1) + (a - 1) * cosW - k
        case .highShelf:
            guard band.gain != 0 else { return nil }
            let k = 2 * sqrt(a) * alphaQ
            b0 = a * ((a + 1) + (a - 1) * cosW + k)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosW)
            b2 = a * ((a + 1) + (a - 1) * cosW - k)
            a0 = (a + 1) - (a - 1) * cosW + k
            a1 = 2 * ((a - 1) - (a + 1) * cosW)
            a2 = (a + 1) - (a - 1) * cosW - k
        case .lowPass:
            b0 = (1 - cosW) / 2; b1 = 1 - cosW; b2 = (1 - cosW) / 2
            a0 = 1 + alphaQ; a1 = -2 * cosW; a2 = 1 - alphaQ
        case .highPass:
            b0 = (1 + cosW) / 2; b1 = -(1 + cosW); b2 = (1 + cosW) / 2
            a0 = 1 + alphaQ; a1 = -2 * cosW; a2 = 1 - alphaQ
        case .bandPass, .notch:
            // The engine maps Notch to a band pass too; see `EQBand.avType`.
            b0 = alphaBW; b1 = 0; b2 = -alphaBW
            a0 = 1 + alphaBW; a1 = -2 * cosW; a2 = 1 - alphaBW
        }
        guard a0 != 0 else { return nil }
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}
