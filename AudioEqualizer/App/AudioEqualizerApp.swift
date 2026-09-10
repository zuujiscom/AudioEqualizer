import SwiftUI

/// AppKit re-adds View and Help after SwiftUI builds the menu bar, so
/// `CommandGroup(replacing:)` cannot remove them — they have to be pulled off
/// `NSApp.mainMenu` once launching is done.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.helpMenu = nil
        DispatchQueue.main.async {
            guard let mainMenu = NSApp.mainMenu else { return }
            for title in ["View", "Help"] {
                if let item = mainMenu.items.first(where: { $0.title == title }) {
                    mainMenu.removeItem(item)
                }
            }
        }
    }
}

@main
struct AudioEqualizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetManager = PresetManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(audioEngine)
                .environmentObject(audioEngine.meters)
                .environmentObject(presetManager)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // File: an EQ has no documents and no second window, so the
            // stock New/Open items are replaced with preset I/O.
            CommandGroup(replacing: .newItem) {
                Button("Save Current as Preset…") {
                    PresetActions.saveCurrent(bands: audioEngine.bands, in: presetManager)
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Import Preset…") {
                    PresetActions.importPreset(into: presetManager)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Export Selected Preset…") {
                    if let preset = presetManager.selectedPreset {
                        PresetActions.export(preset, from: presetManager)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(presetManager.selectedPreset == nil)

                Divider()

                Button("Reveal Presets File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([presetManager.presetsFileURL])
                }
            }

            // View and Help are removed in AppDelegate; About moves to the
            // app menu, where it belongs.

            // Nothing here registers an undo manager, so Undo/Redo were inert.
            // The pasteboard items stay — they are what makes ⌘V work in the
            // preset name and rename dialogs.
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .appInfo) {
                Button("About Audio Equalizer") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Audio Equalizer",
                            .applicationVersion: "1.0.0",
                            .version: "1",
                            .credits: NSAttributedString(string: "Native macOS Equalizer for Apple Silicon")
                        ]
                    )
                }
            }

            CommandMenu("Presets") {
                Section("Built-in") {
                    ForEach(Array(EQPreset.allBuiltin.enumerated()), id: \.element.id) { index, preset in
                        Button(preset.name) {
                            presetManager.selectedPresetID = preset.id
                            audioEngine.applyPreset(preset)
                        }
                        .keyboardShortcut(shortcut(for: index), modifiers: [.command])
                    }
                }

                if !presetManager.customPresets.isEmpty {
                    Section("Custom") {
                        ForEach(presetManager.customPresets) { preset in
                            Button(preset.name) {
                                presetManager.selectedPresetID = preset.id
                                audioEngine.applyPreset(preset)
                            }
                        }
                    }
                }

                Divider()

                Button("Reset EQ to Flat") {
                    audioEngine.resetToFlat()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandMenu("Engine") {
                Button(audioEngine.isRunning ? "Stop Engine" : "Start Engine") {
                    audioEngine.isRunning ? audioEngine.stop() : audioEngine.start()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Divider()

                Button("Refresh Devices") {
                    audioEngine.enumerateDevices()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Copy Diagnostics") {
                    let text = audioEngine.diagnosticsReport()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }

                Divider()

                Section("Output") {
                    Text(audioEngine.outputFormat)
                }
            }
        }
    }
}

/// ⌘1…⌘9 for the first nine built-ins; the rest are click-only.
private func shortcut(for index: Int) -> KeyEquivalent {
    let digits: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    return index < digits.count ? digits[index] : .init("\0")
}
