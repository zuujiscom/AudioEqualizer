import SwiftUI

struct MainView: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var presets: PresetManager

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    SpectrumView()
                    HStack(alignment: .top, spacing: 20) {
                        BandControlsView()
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 20) {
                            PresetSectionView()
                            DeviceSelectionView()
                            StatusView()
                        }
                        .frame(width: 280)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Header Bar

struct HeaderBar: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var presets: PresetManager

    @State private var showPresetPicker = false

    var body: some View {
        HStack(spacing: 12) {
            // Power / engine status
            Button {
                engine.isRunning ? engine.stop() : engine.start()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(engine.isRunning ? Color.green : Color.gray)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(engine.isRunning ? Color.green.opacity(0.15) : Color.gray.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help(engine.isRunning ? "Stop" : "Start")

            Divider().frame(height: 24)

            // Preset picker
            Menu {
                Picker("", selection: $presets.selectedPresetID) {
                    ForEach(presets.allPresets) { preset in
                        Text(preset.name)
                            .tag(Optional<UUID>(preset.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)

                Divider()

                Button("Save Current as Preset…") {
                    saveCurrentAsPreset()
                }
                Button("Import…") { importPreset() }
            } label: {
                Label(
                    presets.selectedPreset?.name ?? "Presets",
                    systemImage: "slider.horizontal.3"
                )
                .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Amplification display (the headline feature)
            HStack(spacing: 8) {
                Image(systemName: engine.masterGain > 1 ? "speaker.wave.2.fill" : "speaker.wave.1.fill")
                    .foregroundStyle(engine.masterGain > 1 ? .green : .secondary)
                Text(String(format: "%+0.1f dB", engine.amplificationDB))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("x%.1f".format1(engine.masterGain))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.08)))

            // Status dot
            Circle()
                .fill(engine.isRunning ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onChange(of: presets.selectedPresetID) { _, newID in
            if let presetID = newID, let preset = presets.preset(withID: presetID) {
                engine.applyPreset(preset)
            }
        }
    }

    private func saveCurrentAsPreset() {
        let alert = NSAlert()
        alert.messageText = "Save Preset"
        alert.informativeText = "Name your custom preset:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.placeholderString = "My Preset"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let name = textField.stringValue
            presets.savePreset(name: name.isEmpty ? "Untitled" : name, bands: engine.bands)
        }
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            presets.importPreset(from: url)
        }
    }
}

private extension String {
    func format1(_ value: Double) -> String {
        String(format: self, value)
    }
}

// MARK: - Volume Slider

struct VolumeSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: $value, in: 0...AudioEngine.maxGain, step: 0.1)
                .frame(width: 120)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .help("Master Gain 0–16x")
    }
}

#Preview {
    MainView()
        .environmentObject(AudioEngine())
        .environmentObject(PresetManager())
}