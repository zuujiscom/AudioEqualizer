// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SpectrumView: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var meters: MeterState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Spectrum Analyzer", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Text(String(format: "Latency: %.1f ms", meters.snapshot.latencyMs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(engine.outputFormat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Drawn in a single Canvas rather than 64 Rectangle views: at 20
            // updates/sec the per-view layout and gradient churn dominated the
            // app's CPU use.
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                context.fill(
                    Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4),
                    with: .color(.black.opacity(0.5))
                )

                let spectrum = meters.snapshot.spectrum
                guard spectrum.count > 0 else { return }

                let inset: CGFloat = 4
                let spacing: CGFloat = 2
                let plotWidth = size.width - inset * 2
                let plotHeight = size.height - inset * 2
                let barWidth = max(1, (plotWidth - spacing * CGFloat(spectrum.count - 1)) / CGFloat(spectrum.count))

                for (index, value) in spectrum.enumerated() {
                    let height = max(2, plotHeight * CGFloat(value))
                    let rect = CGRect(
                        x: inset + CGFloat(index) * (barWidth + spacing),
                        y: size.height - inset - height,
                        width: barWidth,
                        height: height
                    )
                    context.fill(Path(rect), with: .color(Self.barColors[index % Self.barColors.count]))
                }
            }
            .frame(height: 110)

            HStack {
                Spacer()
                Text(engine.isRunning ? "Live" : "Idle")
                    .font(.caption2)
                    .foregroundStyle(engine.isRunning ? Color.green : Color.secondary)
            }
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

    /// Low-to-high frequency colour ramp, built once instead of per frame.
    private static let barColors: [Color] = (0..<64).map { index in
        let t = Double(index) / 63.0
        if t < 0.4 {
            return Color.green.opacity(0.75).mix(with: .teal, by: t / 0.4)
        } else if t < 0.7 {
            return Color.teal.opacity(0.75).mix(with: .yellow, by: (t - 0.4) / 0.3)
        }
        return Color.yellow.opacity(0.75).mix(with: .red, by: (t - 0.7) / 0.3)
    }
}