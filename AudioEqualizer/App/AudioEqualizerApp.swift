import SwiftUI

/// AppKit re-adds View and Help after SwiftUI builds the menu bar, so
/// `CommandGroup(replacing:)` cannot remove them — they have to be pulled off
/// `NSApp.mainMenu` directly.
///
/// Stripping once at launch is not enough: SwiftUI rebuilds the entire main
/// menu whenever `.commands` re-evaluates, and the Engine menu's title depends
/// on `isRunning`, so a rebuild lands every time the engine starts or stops and
/// both menus come back. The strip therefore re-runs on the application update
/// notification, guarded by an item count so the common case is one compare.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var strippedItemCount = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        stripMenus()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stripMenus),
            name: NSApplication.didUpdateNotification,
            object: nil
        )
    }

    @objc private func stripMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard mainMenu.items.count != strippedItemCount else { return }

        for title in ["View", "Help"] {
            if let item = mainMenu.items.first(where: { $0.title == title }) {
                mainMenu.removeItem(item)
            }
        }
        NSApp.helpMenu = nil
        strippedItemCount = mainMenu.items.count
    }
}

@main
struct AudioEqualizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
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

                Divider()

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

            CommandMenu("Visualizer") {
                Button("Open Visualizer") {
                    openVisualizerWindow()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Divider()

                // Selecting a mode also opens the window, so the menu works as
                // a launcher rather than only as a switch for a window already
                // on screen. Auto is a single top-level choice, not a section:
                // a one-item section headed "Auto" containing "Auto" is only
                // confusing, and the header is not clickable.
                Button("Auto (cycle presets)") {
                    UserDefaults.standard.set(VisualizerMode.auto.rawValue, forKey: VisualizerMode.storageKey)
                    openVisualizerWindow()
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Divider()

                ForEach(VisualizerMode.groups) { group in
                    Section(group.id) {
                        ForEach(group.modes) { mode in
                            Button {
                                UserDefaults.standard.set(mode.rawValue, forKey: VisualizerMode.storageKey)
                                openVisualizerWindow()
                            } label: {
                                Text(mode.rawValue)
                            }
                            .keyboardShortcut(mode.shortcut ?? "0", modifiers: [.command, .option])
                        }
                    }
                }
            }
        }

        Window("Visualizer", id: Self.visualizerWindowID) {
            VisualizerWindow()
                .environmentObject(audioEngine)
        }
        .defaultSize(width: 960, height: 600)
    }

    static let visualizerWindowID = "visualizer"

    private func openVisualizerWindow() {
        openWindow(id: Self.visualizerWindowID)
    }
}

/// ⌘1…⌘9 for the first nine built-ins; the rest are click-only.
private func shortcut(for index: Int) -> KeyEquivalent {
    let digits: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    return index < digits.count ? digits[index] : .init("\0")
}
