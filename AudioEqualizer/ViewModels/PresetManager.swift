// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Combine

@MainActor
final class PresetManager: ObservableObject {
    @Published var customPresets: [EQPreset] = []
    @Published var selectedPresetID: UUID?
    @Published var presetName: String = "Custom"

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AudioEqualizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        storageURL = appDir.appendingPathComponent("presets.json")
        loadPresets()
    }

    /// Where custom presets live on disk, for the File > Reveal command.
    var presetsFileURL: URL { storageURL }

    var allPresets: [EQPreset] {
        EQPreset.allBuiltin + customPresets
    }

    var selectedPreset: EQPreset? {
        guard let id = selectedPresetID else { return nil }
        return allPresets.first { $0.id == id }
    }

    func savePreset(name: String, bands: [EQBand]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let preset = EQPreset(name: trimmed, bands: bands)
        customPresets.append(preset)
        selectedPresetID = preset.id
        presetName = trimmed
        persist()
    }

    func updatePreset(_ id: UUID, bands: [EQBand]) {
        guard let idx = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets[idx].bands = bands
        persist()
    }

    func deletePreset(_ id: UUID) {
        customPresets.removeAll { $0.id == id }
        if selectedPresetID == id {
            selectedPresetID = EQPreset.allBuiltin.first?.id
        }
        persist()
    }

    func duplicatePreset(_ id: UUID) {
        guard let original = allPresets.first(where: { $0.id == id }) else { return }
        let copy = EQPreset(name: original.name + " Copy", bands: original.bands)
        customPresets.append(copy)
        selectedPresetID = copy.id
        persist()
    }

    func preset(withID id: UUID) -> EQPreset? {
        allPresets.first { $0.id == id }
    }

    // MARK: - Persistence

    private func loadPresets() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let decoded = try? JSONDecoder().decode([EQPreset].self, from: data) else { return }
        customPresets = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(customPresets) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    func importPreset(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let preset = try? JSONDecoder().decode(EQPreset.self, from: data) else { return }
        customPresets.append(preset)
        selectedPresetID = preset.id
        persist()
    }

    func exportPreset(_ id: UUID, to url: URL) {
        guard let preset = allPresets.first(where: { $0.id == id }) else { return }
        guard let data = try? JSONEncoder().encode(preset) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func exportPresetJSON(_ id: UUID) -> String? {
        guard let preset = allPresets.first(where: { $0.id == id }) else { return nil }
        guard let data = try? JSONEncoder().encode(preset) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}