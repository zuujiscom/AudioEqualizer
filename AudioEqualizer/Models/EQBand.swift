// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import AVFoundation

struct EQBand: Identifiable, Codable, Equatable {
    let id: UUID
    var frequency: Double
    var gain: Double
    var bandwidth: Double
    var filterType: FilterType
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        frequency: Double,
        gain: Double = 0.0,
        bandwidth: Double = 1.0,
        filterType: FilterType = .parametric,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.frequency = frequency
        self.gain = gain
        self.bandwidth = bandwidth
        self.filterType = filterType
        self.isEnabled = isEnabled
    }

    var frequencyLabel: String {
        if frequency >= 1000 {
            return String(format: "%.1fk", frequency / 1000)
        }
        return String(format: "%.0f", frequency)
    }

    enum FilterType: String, Codable, CaseIterable {
        case parametric = "Parametric"
        case lowShelf = "Low Shelf"
        case highShelf = "High Shelf"
        case lowPass = "Low Pass"
        case highPass = "High Pass"
        case bandPass = "Band Pass"
        case notch = "Notch"

        var avType: AVAudioUnitEQFilterType {
            switch self {
            case .parametric: return .parametric
            case .lowShelf: return .lowShelf
            case .highShelf: return .highShelf
            case .lowPass: return .lowPass
            case .highPass: return .highPass
            case .bandPass: return .bandPass
            case .notch: return .bandPass // Notch not available; approximate with band pass
            }
        }

        var shortName: String {
            switch self {
            case .parametric: return "PK"
            case .lowShelf: return "LS"
            case .highShelf: return "HS"
            case .lowPass: return "LP"
            case .highPass: return "HP"
            case .bandPass: return "BP"
            case .notch: return "NT"
            }
        }
    }
}
