import SwiftUI

struct PresetSectionView: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var presets: PresetManager

    @State private var isSaving = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Presets", systemImage: "music.note.list")
                    .font(.headline)
                Spacer()
                Button {
                    isSaving.toggle()
                } label: {
                    Label("Save", systemImage: "plus.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isSaving {
                saveField
            }

            List(selection: $presets.selectedPresetID) {
                Section("Built-in") {
                    ForEach(EQPreset.allBuiltin) { preset in
                        row(for: preset)
                    }
                }

                if !presets.customPresets.isEmpty {
                    Section("Custom") {
                        ForEach(presets.customPresets) { preset in
                            row(for: preset)
                                .contextMenu {
                                    Button("Rename") { rename(preset) }
                                    Button("Duplicate") { presets.duplicatePreset(preset.id) }
                                    Button("Delete", role: .destructive) { presets.deletePreset(preset.id) }
                                    Divider()
                                    Button("Export…") { export(preset) }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private var saveField: some View {
        HStack(spacing: 6) {
            TextField("Preset name…", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            Button("Save") {
                let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                presets.savePreset(name: name.isEmpty ? "Untitled" : name, bands: engine.bands)
                newPresetName = ""
                isSaving = false
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 4)
    }

    private func row(for preset: EQPreset) -> some View {
        HStack {
            Text(preset.name)
                .font(.system(size: 12))
            Spacer()
            if presets.selectedPresetID == preset.id {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            presets.selectedPresetID = preset.id
            engine.applyPreset(preset)
        }
    }

    private func rename(_ preset: EQPreset) {
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

    private func export(_ preset: EQPreset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.name).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            presets.exportPreset(preset.id, to: url)
        }
    }
}

struct StatusView: View {
    @EnvironmentObject private var engine: AudioEngine

    var body: some View {
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

            HStack {
                Spacer()
                Button(engine.isRunning ? "Stop Engine" : "Start Engine") {
                    engine.isRunning ? engine.stop() : engine.start()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(engine.isRunning ? .red : .green)
            }
            .padding(.top, 4)
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