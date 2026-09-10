import SwiftUI

/// Header-bar preset control. Replaces the old sidebar list — selecting a
/// preset only sets `selectedPresetID`; `HeaderBar`'s `onChange` is what
/// applies it, so presets are never applied twice.
struct PresetMenu: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var presets: PresetManager

    var body: some View {
        Menu {
            Section("Built-in") {
                ForEach(EQPreset.allBuiltin) { preset in
                    presetButton(preset)
                }
            }

            if !presets.customPresets.isEmpty {
                Section("Custom") {
                    ForEach(presets.customPresets) { preset in
                        Menu(preset.name) {
                            Button("Apply") { presets.selectedPresetID = preset.id }
                            Divider()
                            Button("Rename…") { PresetActions.rename(preset, in: presets) }
                            Button("Duplicate") { presets.duplicatePreset(preset.id) }
                            Button("Export…") { PresetActions.export(preset, from: presets) }
                            Divider()
                            Button("Delete", role: .destructive) { presets.deletePreset(preset.id) }
                        }
                    }
                }
            }

            Divider()

            Button("Save Current as Preset…") {
                PresetActions.saveCurrent(bands: engine.bands, in: presets)
            }
            Button("Import…") { PresetActions.importPreset(into: presets) }
        } label: {
            Label(presets.selectedPreset?.name ?? "Presets", systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Presets")
    }

    private func presetButton(_ preset: EQPreset) -> some View {
        Button {
            presets.selectedPresetID = preset.id
        } label: {
            if presets.selectedPresetID == preset.id {
                Label(preset.name, systemImage: "checkmark")
            } else {
                Text(preset.name)
            }
        }
    }
}

// MARK: - Status

/// Everything the old `StatusView` panel showed, plus the start/stop and
/// bypass controls, in a header popover.
struct StatusMenu: View {
    @EnvironmentObject private var engine: AudioEngine
    @State private var showStatus = false

    var body: some View {
        Button {
            showStatus.toggle()
        } label: {
            Label(engine.isRunning ? "Running" : "Stopped", systemImage: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(engine.isRunning ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Engine status")
        .popover(isPresented: $showStatus, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Status", systemImage: "info.circle")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    statusRow("Engine", engine.isRunning ? "Running" : "Stopped", engine.isRunning ? .green : .secondary)
                    statusRow("Bypass", engine.isBypassed ? "Active" : "Off", engine.isBypassed ? .orange : .secondary)
                    statusRow("Input", engine.inputFormat, .secondary)
                    statusRow("Output", engine.outputFormat, .secondary)
                    statusRow("Master Gain", String(format: "%.2fx (%+0.1f dB)", engine.masterGain, engine.amplificationDB), engine.masterGain > 1 ? .green : .secondary)
                }
                .font(.system(size: 11))

                Divider()

                HStack {
                    Spacer()

                    Button(engine.isRunning ? "Stop Engine" : "Start Engine") {
                        engine.isRunning ? engine.stop() : engine.start()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isRunning ? .red : .green)
                }
            }
            .padding(14)
            .frame(width: 300)
        }
    }

    private func statusRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

// MARK: - Shared preset actions

/// Shared by the header menu and the menu-bar commands so both routes behave
/// identically.
@MainActor
enum PresetActions {
    static func saveCurrent(bands: [EQBand], in presets: PresetManager) {
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
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            presets.savePreset(name: name.isEmpty ? "Untitled" : name, bands: bands)
        }
    }

    static func rename(_ preset: EQPreset, in presets: PresetManager) {
        let alert = NSAlert()
        alert.messageText = "Rename Preset"
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        tf.stringValue = preset.name
        alert.accessoryView = tf
        alert.window.initialFirstResponder = tf

        if alert.runModal() == .alertFirstButtonReturn {
            if let idx = presets.customPresets.firstIndex(where: { $0.id == preset.id }) {
                presets.customPresets[idx].name = tf.stringValue
            }
        }
    }

    static func export(_ preset: EQPreset, from presets: PresetManager) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.name).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            presets.exportPreset(preset.id, to: url)
        }
    }

    static func importPreset(into presets: PresetManager) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            presets.importPreset(from: url)
        }
    }
}
