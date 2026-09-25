// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Combine

/// Imported MilkDrop presets, read from Application Support at launch.
///
/// They live in a user folder rather than in the app bundle: the preset packs
/// are community works with unclear licensing, so they are something the user
/// brings, not something this project redistributes.
@MainActor
final class MilkdropLibrary: ObservableObject {
    @Published private(set) var presets: [MilkdropPreset] = []
    @Published private(set) var lastImportSummary: String?

    static let selectionKey = "visualizerMilkdropPreset"

    let folderURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        folderURL = appSupport
            .appendingPathComponent("AudioEqualizer", isDirectory: true)
            .appendingPathComponent("milkdrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        reload()
    }

    var isEmpty: Bool { presets.isEmpty }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil
        )) ?? []
        presets = urls
            .filter { $0.pathExtension.lowercased() == "milk" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { MilkdropPreset(contentsOf: $0) }
    }

    /// Copies `.milk` files in, recursing into any folders chosen, then reloads.
    /// Files that carry no equations are skipped — their header alone is all
    /// defaults and would render as a motionless frame.
    func importPresets(from sources: [URL]) {
        var copied = 0
        var skipped = 0

        func consider(_ url: URL) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
            if isDirectory.boolValue {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil
                )) ?? []
                children.forEach(consider)
                return
            }
            guard url.pathExtension.lowercased() == "milk" else { return }
            guard MilkdropPreset(contentsOf: url) != nil else { skipped += 1; return }

            let destination = folderURL.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                copied += 1
            } catch {
                skipped += 1
            }
        }

        sources.forEach(consider)
        reload()
        lastImportSummary = skipped > 0
            ? "Imported \(copied), skipped \(skipped)"
            : "Imported \(copied)"
    }

    func removeAll() {
        for url in (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension.lowercased() == "milk" {
            try? FileManager.default.removeItem(at: url)
        }
        reload()
    }
}
