// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var presets: PresetManager

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                VStack(spacing: 14) {
                    PresetChips()
                    SpectrumView()
                    BandControlsView()
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        // Up into the hidden title bar, so the header shares its row with
        // the traffic lights instead of sitting under an empty strip.
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Header Bar

/// Power, status, devices, presets, bypass and the visualizer all live here;
/// there is no sidebar, so the graph and the faders get the full width. The
/// window has no title bar of its own — this row is drawn up into it, which is
/// why it starts clear of the traffic lights.
struct HeaderBar: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var meters: MeterState
    @EnvironmentObject private var presets: PresetManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 10) {
            PowerButton()

            VStack(alignment: .leading, spacing: 1) {
                Text("Audio Equalizer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                statusLine
            }
            .padding(.trailing, 6)

            Spacer(minLength: 8)

            DeviceMenu()
            PresetMenu()

            Button {
                engine.toggleBypass()
            } label: {
                Label("Bypass", systemImage: engine.isBypassed ? "circle.slash.fill" : "circle.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(engine.isBypassed ? Theme.amber : Color.white.opacity(0.85))
                    .pill(active: engine.isBypassed, tint: Theme.amber)
            }
            .buttonStyle(.plain)
            .help("Hear the audio without the EQ, to compare  (⌘B)")

            Button {
                openWindow(id: AudioEqualizerApp.visualizerWindowID)
            } label: {
                Label("Visualizer", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Theme.signal).opacity(0.85))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open the visualizer  (⇧⌘V)")

            StatusMenu()
        }
        .padding(.leading, 84)
        .padding(.trailing, 14)
        .frame(height: 54)
        .background(Color.white.opacity(0.025))
        .onChange(of: presets.selectedPresetID) { _, newID in
            if let presetID = newID, let preset = presets.preset(withID: presetID) {
                engine.applyPreset(preset)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = engine.routeErrorMessage {
            Text(error)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.amber)
                .lineLimit(1)
        } else if engine.isRunning {
            HStack(spacing: 5) {
                Circle().fill(engine.isBypassed ? Theme.amber : Theme.mint).frame(width: 6, height: 6)
                Text(engine.isBypassed ? "Bypassed" : "Live")
                    .foregroundStyle(engine.isBypassed ? Theme.amber : Theme.mint)
                Text("· \(engine.outputFormat)")
                    .foregroundStyle(.white.opacity(0.45))
            }
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
        } else {
            Text("Off — system audio is untouched")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }
}

// MARK: - Power

struct PowerButton: View {
    @EnvironmentObject private var engine: AudioEngine

    var body: some View {
        Button {
            engine.isRunning ? engine.stop() : engine.start()
        } label: {
            ZStack {
                Circle()
                    .fill(engine.isRunning ? Theme.mint.opacity(0.18) : Color.white.opacity(0.06))
                Circle()
                    .strokeBorder(engine.isRunning ? Theme.mint.opacity(0.9) : Color.white.opacity(0.18),
                                  lineWidth: 1.5)
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(engine.isRunning ? Theme.mint : Color.white.opacity(0.6))
            }
            .frame(width: 34, height: 34)
            .shadow(color: engine.isRunning ? Theme.mint.opacity(0.55) : .clear, radius: 8)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: engine.isRunning)
        .help(engine.isRunning ? "Stop  (⌘↩)" : "Start  (⌘↩)")
    }
}

#Preview {
    MainView()
        .environmentObject(AudioEngine())
        .environmentObject(AudioEngine().meters)
        .environmentObject(PresetManager())
        .environmentObject(DeviceProfileStore())
}
