// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A preset's tonal shape, held independently of any particular band layout.
///
/// Built-in presets are curves rather than fixed band lists for two reasons.
/// Selecting one no longer drags the EQ back to ten bands, so a preset can be
/// auditioned in 10-, 15- or 31-band mode and sound the same; and a curve can
/// be drawn as a smooth contour instead of the blocky per-decade steps the
/// presets used to be.
struct EQCurve: Codable, Equatable {
    struct Point: Codable, Equatable {
        var frequency: Double
        var gain: Double
    }

    /// Control points in ascending frequency order.
    var points: [Point]

    init(_ points: [(Double, Double)]) {
        self.points = points
            .map { Point(frequency: $0.0, gain: $0.1) }
            .sorted { $0.frequency < $1.frequency }
    }

    /// Gain at `frequency`, interpolated between control points on a log axis —
    /// the axis both the ear and the band layouts are spaced on, so a straight
    /// line between 100 Hz and 1 kHz passes through 316 Hz, not 550 Hz.
    /// Outside the outermost points the curve is held flat.
    func gain(at frequency: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        guard frequency > first.frequency else { return first.gain }
        guard frequency < last.frequency else { return last.gain }

        for index in 1..<points.count {
            let upper = points[index]
            guard frequency <= upper.frequency else { continue }

            let lower = points[index - 1]
            let span = log10(upper.frequency) - log10(lower.frequency)
            guard span > 0 else { return upper.gain }

            let position = (log10(frequency) - log10(lower.frequency)) / span
            let gain = lower.gain + position * (upper.gain - lower.gain)
            // Round off interpolation noise so the readouts stay tidy.
            return (gain * 10).rounded() / 10
        }
        return last.gain
    }

    /// Re-gains an existing band layout. Frequency, Q, filter type and the
    /// per-band on/off state are the user's, so only the gain is replaced.
    func applied(to bands: [EQBand]) -> [EQBand] {
        bands.map { band in
            var updated = band
            updated.gain = gain(at: band.frequency)
            return updated
        }
    }
}

/// Built-in and custom presets
struct EQPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bands: [EQBand]
    var isBuiltin: Bool
    var dateCreated: Date
    /// Present on built-in presets. Custom and imported presets carry only a
    /// band list, so this decodes as `nil` for them and for older JSON.
    var curve: EQCurve?

    init(id: UUID = UUID(), name: String, bands: [EQBand], isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.bands = bands
        self.isBuiltin = isBuiltin
        self.dateCreated = Date()
    }

    /// Built-in initialiser. `bands` is materialised over the default 10-band
    /// layout so anything reading `preset.bands` directly (export, previews)
    /// still works; `applyPreset` prefers the curve.
    init(id: UUID = UUID(), name: String, curve: EQCurve, isBuiltin: Bool = true) {
        self.id = id
        self.name = name
        self.bands = curve.applied(to: EQPreset.defaultBands)
        self.isBuiltin = isBuiltin
        self.dateCreated = Date()
        self.curve = curve
    }

    // MARK: - Built-in Presets
    //
    // Each preset is a contour through nine control points spanning the audible
    // range. They are written to be roughly tone-neutral in level: a preset that
    // lifts everything is just a volume control, and on top of the master gain
    // it only buys clipping. Where a curve boosts one region it gives some back
    // in another.

    static let flat = EQPreset(name: "Flat", curve: EQCurve([
        (20, 0), (60, 0), (150, 0), (400, 0), (1_000, 0),
        (2_500, 0), (5_000, 0), (10_000, 0), (20_000, 0)
    ]))

    /// A low shelf that stops before the lower mids, plus a small dip at 2 kHz
    /// so the extra weight does not swallow vocal clarity.
    static let bassBoost = EQPreset(name: "Bass Boost", curve: EQCurve([
        (20, 7), (60, 6), (150, 3.5), (400, 1), (1_000, 0),
        (2_500, -1), (5_000, -0.5), (10_000, 0), (20_000, 0)
    ]))

    static let trebleBoost = EQPreset(name: "Treble Boost", curve: EQCurve([
        (20, 0), (60, 0), (150, -0.5), (400, -1), (1_000, 0),
        (2_500, 1.5), (5_000, 3.5), (10_000, 5), (20_000, 5.5)
    ]))

    /// Thins the low end and lifts the 1–3 kHz presence region where
    /// intelligibility lives, then eases off the sibilance above 8 kHz.
    static let vocal = EQPreset(name: "Vocal", curve: EQCurve([
        (20, -4), (60, -3), (150, -1), (400, 1), (1_000, 3),
        (2_500, 4), (5_000, 2), (10_000, -1), (20_000, -3)
    ]))

    /// Classic smile curve with a presence lift rather than a flat treble shelf.
    static let rock = EQPreset(name: "Rock", curve: EQCurve([
        (20, 4), (60, 4.5), (150, 2), (400, -1.5), (1_000, -1),
        (2_500, 1.5), (5_000, 3.5), (10_000, 4), (20_000, 3)
    ]))

    static let pop = EQPreset(name: "Pop", curve: EQCurve([
        (20, -1), (60, 0.5), (150, 1.5), (400, 2.5), (1_000, 2),
        (2_500, 1), (5_000, 0), (10_000, 1.5), (20_000, 2)
    ]))

    /// Gentle throughout: jazz recordings are usually already well balanced.
    static let jazz = EQPreset(name: "Jazz", curve: EQCurve([
        (20, 3), (60, 2.5), (150, 1), (400, 0), (1_000, 0.5),
        (2_500, 1.5), (5_000, 2), (10_000, 2), (20_000, 1)
    ]))

    /// Extends both ends and steps the mids back, for hall ambience.
    static let classical = EQPreset(name: "Classical", curve: EQCurve([
        (20, 3), (60, 2.5), (150, 1), (400, 0), (1_000, -0.5),
        (2_500, -0.5), (5_000, 1.5), (10_000, 3), (20_000, 3.5)
    ]))

    static let electronic = EQPreset(name: "Electronic", curve: EQCurve([
        (20, 5.5), (60, 5), (150, 2), (400, -1), (1_000, -0.5),
        (2_500, 1), (5_000, 2.5), (10_000, 4), (20_000, 4.5)
    ]))

    /// Sub-bass weight with the 300–600 Hz mud scooped out.
    static let hipHop = EQPreset(name: "Hip-Hop", curve: EQCurve([
        (20, 6.5), (60, 6), (150, 3), (400, -1.5), (1_000, -0.5),
        (2_500, 1), (5_000, 2), (10_000, 2.5), (20_000, 2)
    ]))

    /// A narrow band around 200–600 Hz, rolled off hard at both ends.
    static let loFi = EQPreset(name: "Lo-Fi", curve: EQCurve([
        (20, -6), (60, 0), (150, 3), (400, 2.5), (1_000, 0),
        (2_500, -2.5), (5_000, -6), (10_000, -10), (20_000, -13)
    ]))

    /// Body and string detail for unamplified instruments.
    static let acoustics = EQPreset(name: "Acoustic", curve: EQCurve([
        (20, 0), (60, 2), (150, 1.5), (400, -0.5), (1_000, 0.5),
        (2_500, 2), (5_000, 2.5), (10_000, 2), (20_000, 1)
    ]))

    /// Equal-loudness compensation: the ear loses both ends at low listening
    /// levels, so this restores them and pulls the mids down to compensate.
    static let loudness = EQPreset(name: "Loudness", curve: EQCurve([
        (20, 8), (60, 6), (150, 3), (400, 0), (1_000, -1.5),
        (2_500, -0.5), (5_000, 3), (10_000, 6), (20_000, 7)
    ]))

    /// Tames the raised bass and 8–12 kHz peak most consumer headphones ship
    /// with, moving them toward a neutral response.
    static let headphones = EQPreset(name: "Headphones", curve: EQCurve([
        (20, -2.5), (60, -1.5), (150, 0), (400, 1), (1_000, 2),
        (2_500, 2.5), (5_000, 0), (10_000, -2.5), (20_000, -3)
    ]))

    /// Compensates for small desktop cabinets: no real low end, and a dip in
    /// the upper mids from the enclosure.
    static let speakers = EQPreset(name: "Speakers", curve: EQCurve([
        (20, 4), (60, 4), (150, 1), (400, -1), (1_000, 0),
        (2_500, 1.5), (5_000, 3), (10_000, 4), (20_000, 4)
    ]))

    /// Speech: high-pass away rumble, lift articulation, drop the air band.
    static let podcast = EQPreset(name: "Podcast/Voice", curve: EQCurve([
        (20, -9), (60, -6), (150, -2), (400, 1), (1_000, 4),
        (2_500, 5), (5_000, 3), (10_000, -1), (20_000, -4)
    ]))

    /// For listening quietly late: less bass to travel through walls and less
    /// top end to startle, with the mids kept forward so dialogue survives.
    static let nightMode = EQPreset(name: "Night Mode", curve: EQCurve([
        (20, -7), (60, -5), (150, -1.5), (400, 1), (1_000, 2),
        (2_500, 2), (5_000, 0), (10_000, -4), (20_000, -7)
    ]))

    static let allBuiltin: [EQPreset] = [
        flat, bassBoost, trebleBoost, vocal, rock, pop,
        jazz, classical, electronic, hipHop, loFi,
        acoustics, loudness, headphones, speakers, podcast, nightMode
    ]

    /// Standard 10-band graphic EQ frequencies
    static let defaultFrequencies: [Double] = [
        31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    /// Extended 31-band graphic EQ frequencies
    static let extendedFrequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
        2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    /// 15-band EQ frequencies
    static let fifteenBandFrequencies: [Double] = [
        25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600,
        2500, 4000, 6300, 10000, 16000
    ]

    static var defaultBands: [EQBand] {
        defaultFrequencies.map { EQBand(frequency: $0) }
    }
}
