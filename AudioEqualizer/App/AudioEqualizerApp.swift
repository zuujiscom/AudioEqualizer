import SwiftUI

@main
struct AudioEqualizerApp: App {
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
            CommandGroup(after: .newItem) {
                Button("Reset EQ to Flat") {
                    audioEngine.resetToFlat()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Audio Equalizer Help") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Audio Equalizer",
                            .applicationVersion: "1.0.0",
                            .version: "1",
                            .credits: "Native macOS Equalizer for Apple Silicon"
                        ]
                    )
                }
            }
        }
    }
}
