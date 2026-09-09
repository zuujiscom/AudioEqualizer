import SwiftUI
import CoreAudio

struct DeviceSelectionView: View {
    @EnvironmentObject private var engine: AudioEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Devices", systemImage: "cable.connector")
                    .font(.headline)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OUTPUT")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(currentOutputName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FORMAT")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(engine.outputFormat)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
            }

            if let routeError = engine.routeErrorMessage {
                Text("⚠︎ \(routeError)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            HStack {
                Button("Refresh Devices") { engine.enumerateDevices() }
                    .controlSize(.small)
                Spacer()
                Text(engine.isRunning ? "✓ Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(engine.isRunning ? Color.green : Color.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var currentOutputName: String {
        guard let device = engine.availableOutputDevices.first(where: { $0.id == engine.selectedOutputDeviceID }) else {
            return "—"
        }
        return device.isBuiltIn ? "\(device.name)  (Built-in)" : device.name
    }
}