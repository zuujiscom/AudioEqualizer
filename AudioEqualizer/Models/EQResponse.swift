// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The combined frequency response of a set of bands: a model of what
/// `AVAudioUnitEQ` does, built from the standard audio-EQ-cookbook biquads.
/// For parametric bands it is not an approximation — measured against the
/// real unit rendered offline, it agrees to within 0.01 dB.
///
/// It has two jobs. It draws the curve, and it works out the gains the unit
/// is actually given (`compensated`), which is why its accuracy matters.
enum EQResponse {
    // MARK: Gain compensation

    /// The bands as the EQ unit should be set: the same list, with each gain
    /// replaced by the one that makes the *summed* response equal the band's
    /// own gain at its own frequency.
    ///
    /// Neighbouring bands overlap, so setting every band to +6 dB does not
    /// give +6 dB. A fader's value is therefore treated as what you want to
    /// hear at that frequency, and this solves for the gains that deliver it.
    /// That in turn lets the bands be wide enough to blend smoothly, which is
    /// what removes the ripple between them.
    ///
    /// Only enabled parametric bands take part; a shelf or a pass filter has
    /// no single frequency at which "its gain" means anything. A fader near
    /// the ±24 dB limit can ask for more than the unit can give, in which case
    /// the result is as close as the limit allows and the curve shows it.
    static func compensated(_ bands: [EQBand], sampleRate: Double = 48_000) -> [EQBand] {
        if let memo, memo.sampleRate == sampleRate, memo.input == bands { return memo.output }

        let active = bands.indices.filter { bands[$0].isEnabled && bands[$0].filterType == .parametric }
        var output = bands
        if active.count > 1, active.contains(where: { bands[$0].gain != 0 }) {
            let solved = solve(active.map { bands[$0] }, sampleRate: sampleRate)
            for (slot, index) in active.enumerated() { output[index].gain = solved[slot] }
        }
        memo = (bands, sampleRate, output)
        return output
    }

    /// The last answer. The graph asks thirty times a second and the bands
    /// rarely change between frames. Main thread only, like its callers.
    private static var memo: (input: [EQBand], sampleRate: Double, output: [EQBand])?

    /// Fixed-point iteration: nudge every gain by its band's remaining error.
    /// A decibel response is close to linear in the gains, so this converges
    /// in a handful of rounds; the step is scaled by how much the bands
    /// overlap so it cannot overshoot.
    private static func solve(_ bands: [EQBand], sampleRate: Double) -> [Double] {
        let count = bands.count
        let angular = bands.map { 2 * Double.pi * min($0.frequency, sampleRate * 0.499) / sampleRate }
        let targets = bands.map(\.gain)

        func responses(_ gains: [Double]) -> [Double] {
            var total = [Double](repeating: 0, count: count)
            for source in 0..<count {
                var band = bands[source]
                band.gain = gains[source]
                guard let biquad = section(for: band, sampleRate: sampleRate) else { continue }
                for probe in 0..<count { total[probe] += biquad.decibels(at: angular[probe]) }
            }
            return total
        }

        // How much one decibel on every band adds up to at the busiest band.
        let overlap = responses([Double](repeating: 1, count: count)).max() ?? 1
        let step = min(1, 1.6 / max(1, overlap))

        var gains = targets
        for _ in 0..<60 {
            let current = responses(gains)
            var worst = 0.0
            for index in 0..<count {
                let error = targets[index] - current[index]
                worst = max(worst, abs(error))
                gains[index] = min(24, max(-24, gains[index] + step * error))
            }
            if worst < 0.01 { break }
        }
        return gains
    }

    // MARK: Response

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

    /// Sections for every enabled band, at the compensated gains the unit is
    /// really given. Disabled bands are skipped, exactly as the engine
    /// bypasses them.
    static func sections(for bands: [EQBand], sampleRate: Double = 48_000) -> [Biquad] {
        compensated(bands, sampleRate: sampleRate).compactMap { band in
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
