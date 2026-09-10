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
                    BandControlsView()
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Header Bar

/// Presets, devices, and status all live here now; the former right-hand
/// column is gone, so the band sliders get the full window width.
struct HeaderBar: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var presets: PresetManager

    var body: some View {
        HStack(spacing: 10) {
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

            PresetMenu()
            DeviceMenu()
            StatusMenu()

            Spacer()

            // Amplification display (the headline feature)
            HStack(spacing: 8) {
                Image(systemName: engine.masterGain > 1 ? "speaker.wave.2.fill" : "speaker.wave.1.fill")
                    .foregroundStyle(engine.masterGain > 1 ? .green : .secondary)
                Text(String(format: "%+0.1f dB", engine.amplificationDB))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(String(format: "x%.1f", engine.masterGain))
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
        .environmentObject(AudioEngine().meters)
        .environmentObject(PresetManager())
}
