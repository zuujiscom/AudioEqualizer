import SwiftUI
import CoreAudio

/// Header-bar device readout. `selectedOutputDeviceID` is `private(set)` and
/// tracks the system default output, so this stays informational — the only
/// action is a re-enumerate.
struct DeviceMenu: View {
    @EnvironmentObject private var engine: AudioEngine

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

            Button("Refresh Devices") { engine.enumerateDevices() }
        } label: {
            Label(currentOutputName, systemImage: engine.routeErrorMessage == nil ? "cable.connector" : "exclamationmark.triangle.fill")
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
