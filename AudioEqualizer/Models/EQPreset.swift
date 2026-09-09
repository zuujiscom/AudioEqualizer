import Foundation

/// Built-in and custom presets
struct EQPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bands: [EQBand]
    var isBuiltin: Bool
    var dateCreated: Date

    init(id: UUID = UUID(), name: String, bands: [EQBand], isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.bands = bands
        self.isBuiltin = isBuiltin
        self.dateCreated = Date()
    }

    // MARK: - Built-in Presets

    static let flat = EQPreset(
        name: "Flat",
        bands: EQPreset.defaultBands.map { $0 },
        isBuiltin: true
    )

    static let bassBoost = EQPreset(
        name: "Bass Boost",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            if band.frequency <= 250 {
                b.gain = band.frequency <= 60 ? 8 : 5
            }
            return b
        },
        isBuiltin: true
    )

    static let trebleBoost = EQPreset(
        name: "Treble Boost",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            if band.frequency >= 2000 {
                b.gain = band.frequency >= 8000 ? 8 : 5
            }
            return b
        },
        isBuiltin: true
    )

    static let vocal = EQPreset(
        name: "Vocal",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            if band.frequency >= 300 && band.frequency <= 4000 {
                b.gain = 4
            }
            return b
        },
        isBuiltin: true
    )

    static let rock = EQPreset(
        name: "Rock",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = 6
            case 100..<300: b.gain = 3
            case 300..<1000: b.gain = -2
            case 1000..<4000: b.gain = 2
            case 4000..<8000: b.gain = 5
            default: b.gain = 4
            }
            return b
        },
        isBuiltin: true
    )

    static let pop = EQPreset(
        name: "Pop",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = 3
            case 300..<2000: b.gain = -2
            case 2000..<6000: b.gain = 4
            default: b.gain = 3
            }
            return b
        },
        isBuiltin: true
    )

    static let jazz = EQPreset(
        name: "Jazz",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = 4
            case 100..<300: b.gain = 2
            case 1000..<4000: b.gain = 3
            case 4000..<10000: b.gain = 4
            default: b.gain = 2
            }
            return b
        },
        isBuiltin: true
    )

    static let classical = EQPreset(
        name: "Classical",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = 5
            case 100..<300: b.gain = 3
            case 300..<1000: b.gain = -1
            case 1000..<4000: b.gain = -2
            case 4000..<10000: b.gain = 2
            default: b.gain = 5
            }
            return b
        },
        isBuiltin: true
    )

    static let electronic = EQPreset(
        name: "Electronic",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = 7
            case 100..<300: b.gain = 4
            case 300..<1000: b.gain = -1
            case 1000..<4000: b.gain = 3
            case 4000..<8000: b.gain = 5
            default: b.gain = 6
            }
            return b
        },
        isBuiltin: true
    )

    static let hipHop = EQPreset(
        name: "Hip-Hop",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = 7
            case 100..<300: b.gain = 5
            case 300..<1000: b.gain = -2
            case 1000..<4000: b.gain = 1
            case 4000..<8000: b.gain = 3
            default: b.gain = 2
            }
            return b
        },
        isBuiltin: true
    )

    static let loFi = EQPreset(
        name: "Lo-Fi",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = 6
            case 100..<300: b.gain = 3
            case 300..<1000: b.gain = 2
            case 1000..<3000: b.gain = -1
            case 3000..<8000: b.gain = -3
            default: b.gain = -5
            }
            return b
        },
        isBuiltin: true
    )

    static let acoustics = EQPreset(
        name: "Acoustic",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<200: b.gain = 3
            case 200..<500: b.gain = 4
            case 500..<2000: b.gain = 2
            case 2000..<6000: b.gain = 3
            default: b.gain = 4
            }
            return b
        },
        isBuiltin: true
    )

    static let loudness = EQPreset(
        name: "Loudness",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = 8
            case 100..<200: b.gain = 4
            case 200..<500: b.gain = 0
            case 500..<2000: b.gain = -2
            case 2000..<4000: b.gain = 0
            case 4000..<10000: b.gain = 5
            default: b.gain = 7
            }
            return b
        },
        isBuiltin: true
    )

    static let headphones = EQPreset(
        name: "Headphones",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<60: b.gain = -3
            case 60..<250: b.gain = 0
            case 250..<1000: b.gain = 2
            case 1000..<4000: b.gain = 3
            case 4000..<10000: b.gain = 1
            default: b.gain = -2
            }
            return b
        },
        isBuiltin: true
    )

    static let speakers = EQPreset(
        name: "Speakers",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<80: b.gain = 5
            case 80..<300: b.gain = 2
            case 300..<2000: b.gain = 0
            case 2000..<6000: b.gain = 3
            default: b.gain = 5
            }
            return b
        },
        isBuiltin: true
    )

    static let podcast = EQPreset(
        name: "Podcast/Voice",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<100: b.gain = -5
            case 100..<300: b.gain = -2
            case 300..<3000: b.gain = 5
            case 3000..<6000: b.gain = 3
            default: b.gain = -2
            }
            return b
        },
        isBuiltin: true
    )

    static let nightMode = EQPreset(
        name: "Night Mode",
        bands: EQPreset.defaultBands.map { band in
            var b = band
            switch band.frequency {
            case ..<200: b.gain = 3
            case 200..<1000: b.gain = 1
            case 1000..<4000: b.gain = -2
            case 4000..<8000: b.gain = -4
            default: b.gain = -6
            }
            return b
        },
        isBuiltin: true
    )

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
