// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import CoreAudio

/// Header-bar device readout. `selectedOutputDeviceID` is `private(set)` and
/// tracks the system default output, so this stays informational — the only
/// action is a re-enumerate.
struct DeviceMenu: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var profiles: DeviceProfileStore

    var body: some View {
        Menu {
            Section("Output") {
                Text(currentOutputName)
                Text(engine.outputFormat)
            }

            Section("Tap input") {
                Text(engine.inputFormat)
            }

            if let routeError = engine.routeErrorMessage {
                Section("Route error") {
                    Text(routeError)
                }
            }

            Divider()

            Section("EQ profile") {
                Toggle("Remember EQ per device", isOn: $profiles.isEnabled)

                Button(engine.currentDeviceHasProfile ? "Update profile for this device" : "Save profile for this device") {
                    engine.captureProfileForCurrentDevice()
                }
                .disabled(!profiles.isEnabled)

                Button("Forget profile for this device") {
                    engine.forgetProfileForCurrentDevice()
                }
                .disabled(!engine.currentDeviceHasProfile)

                if !profiles.sortedProfiles.isEmpty {
                    Menu("Saved profiles") {
                        ForEach(profiles.sortedProfiles) { profile in
                            Text("\(profile.deviceName) — \(profile.bands.count) bands")
                        }
                        Divider()
                        Button("Forget all", role: .destructive) { profiles.removeAll() }
                    }
                }
            }

            Divider()

            Button("Refresh Devices") { engine.enumerateDevices() }
        } label: {
            Label(
                currentOutputName,
                systemImage: engine.routeErrorMessage != nil
                    ? "exclamationmark.triangle.fill"
                    : (engine.currentDeviceHasProfile && profiles.isEnabled ? "person.crop.circle.badge.checkmark" : "cable.connector")
            )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(engine.routeErrorMessage == nil ? Color.primary : Color.orange)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(engine.routeErrorMessage ?? "Output device")
    }

    private var currentOutputName: String {
        guard let device = engine.availableOutputDevices.first(where: { $0.id == engine.selectedOutputDeviceID }) else {
            return "—"
        }
        return device.isBuiltIn ? "\(device.name)  (Built-in)" : device.name
    }
}
