// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A saved EQ state belonging to one output device.
///
/// Keyed by the Core Audio device UID rather than by name: names are not
/// unique and change with the hardware's whims, while the UID is stable across
/// reconnects. The name is stored only so profiles for absent devices can still
/// be listed in the UI.
struct DeviceProfile: Codable, Identifiable, Equatable {
    var deviceUID: String
    var deviceName: String
    var bands: [EQBand]
    var masterGain: Double
    var updatedAt: Date

    var id: String { deviceUID }
}
