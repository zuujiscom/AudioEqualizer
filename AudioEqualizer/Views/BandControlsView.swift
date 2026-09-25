// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct BandControlsView: View {
    @EnvironmentObject private var engine: AudioEngine
    @State private var showBandDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Equalizer Bands", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()

                Picker("Bands", selection: bandCountSelection) {
                    Text("10-Band").tag(10)
                    Text("15-Band").tag(15)
                    Text("31-Band").tag(31)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button {
                    showBandDetails.toggle()
                } label: {
                    Image(systemName: showBandDetails ? "slider.horizontal.3" : "chevron.down.circle")
                }
                .buttonStyle(.plain)
                .help("Show band details")
            }

            amplificationRow

            bandRow

            if showBandDetails {
                bandDetailsGrid
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

    /// The bands are laid out to fit the panel: columns shrink toward
    /// `minColumnWidth` as the band count grows, and only fall back to
    /// horizontal scrolling once even the narrowest column no longer fits.
    /// A fixed column width made 31-band mode several screens wide.
    private static let columnSpacing: CGFloat = 2
    private static let minColumnWidth: CGFloat = 20
    private static let maxColumnWidth: CGFloat = 72

    private var bandRow: some View {
        GeometryReader { geo in
            let count = max(1, engine.bands.count)
            let gaps = Self.columnSpacing * CGFloat(count - 1)
            let ideal = (geo.size.width - gaps) / CGFloat(count)
            let column = min(Self.maxColumnWidth, max(Self.minColumnWidth, ideal))
            let fits = column * CGFloat(count) + gaps <= geo.size.width + 0.5

            let row = HStack(alignment: .bottom, spacing: Self.columnSpacing) {
                ForEach(Array(engine.bands.enumerated()), id: \.element.id) { index, _ in
                    BandSlider(
                        band: binding(forIndex: index),
                        index: index,
                        columnWidth: column
                    )
                }
            }

            if fits {
                row.frame(width: geo.size.width, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: true) { row }
            }
        }
        .frame(height: BandSlider.rowHeight)
        .padding(.vertical, 6)
    }

    private var amplificationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $engine.masterGain, in: 0.25...AudioEngine.maxGain, step: 0.05)
                .tint(engine.masterGain > 1.5 ? .green : .orange)
            Text(String(format: "%+0.1f dB", engine.amplificationDB))
                .font(.caption.monospacedDigit())
                .foregroundStyle(engine.amplificationDB > 0 ? Color.green : Color.secondary)
                .frame(width: 58, alignment: .trailing)
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    engine.masterGain = 1.0
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help("Reset amplification")
        }
        .padding(.horizontal, 2)
    }

    private var bandCountSelection: Binding<Int> {
        Binding(
            get: { engine.bands.count },
            set: { newCount in
                // Deferred: mutating engine state inside a binding setter runs
                // during the view update, which SwiftUI warns about.
                DispatchQueue.main.async { engine.setBandCount(newCount) }
            }
        )
    }

    /// Bindings are captured by index, but the band count can shrink underneath
    /// them (switching 31-band → 15-band), so both sides must tolerate an index
    /// that no longer exists.
    private func binding(forIndex index: Int) -> Binding<BandEditable> {
        Binding(
            get: {
                guard index < engine.bands.count else {
                    return BandEditable(gain: 0, frequency: 0, bandwidth: 1, filterType: .parametric, isEnabled: false)
                }
                let band = engine.bands[index]
                return BandEditable(
                    gain: band.gain,
                    frequency: band.frequency,
                    bandwidth: band.bandwidth,
                    filterType: band.filterType,
                    isEnabled: band.isEnabled
                )
            },
            set: { editable in
                guard index < engine.bands.count else { return }
                engine.bands[index].gain = editable.gain
                engine.bands[index].frequency = editable.frequency
                engine.bands[index].bandwidth = editable.bandwidth
                engine.bands[index].filterType = editable.filterType
                engine.bands[index].isEnabled = editable.isEnabled
                engine.applyBandToNode(index)
            }
        )
    }

    private var bandDetailsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Freq").font(.caption2).foregroundStyle(.secondary)
                Text("Gain").font(.caption2).foregroundStyle(.secondary)
                Text("Q").font(.caption2).foregroundStyle(.secondary)
                Text("Type").font(.caption2).foregroundStyle(.secondary)
                Text("On").font(.caption2).foregroundStyle(.secondary)
            }

            ForEach(Array(engine.bands.enumerated()), id: \.element.id) { index, band in
                GridRow {
                    Text(band.frequencyLabel)
                        .font(.caption.monospacedDigit())
                    Text(String(format: "%+0.1f dB", band.gain))
                        .font(.caption.monospacedDigit())
                    Text(String(format: "%.2f", band.bandwidth))
                        .font(.caption.monospacedDigit())
                    Text(band.filterType.shortName)
                        .font(.caption)
                    Toggle("", isOn: Binding(
                        get: { band.isEnabled },
                        set: { engine.toggleBand(index, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Individual Band Slider

struct BandSlider: View {
    @Binding var band: BandEditable
    let index: Int
    /// Horizontal space this column may occupy — see `BandControlsView.bandRow`.
    let columnWidth: CGFloat

    /// Track length of the (rotated) vertical slider.
    static let trackLength: CGFloat = 130
    /// Total height of a band column, so the row can be given a fixed height.
    static let rowHeight: CGFloat = trackLength + 56

    private let gainRange: ClosedRange<Double> = -24...24

    /// Narrow columns (31-band mode) can't fit the full "+12.0" readout, so the
    /// labels scale down and the gain value drops its decimal.
    private var isCompact: Bool { columnWidth < 30 }

    private var gainText: String {
        isCompact
            ? String(format: "%+.0f", band.gain)
            : String(format: "%+0.1f", band.gain)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Gain value label
            Text(gainText)
                .font(.system(size: isCompact ? 8 : 9, weight: band.gain == 0 ? .regular : .semibold))
                .monospacedDigit()
                .foregroundStyle(gainColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Slider. A SwiftUI Slider is always horizontal, so it is laid out
            // at its full track length and then rotated upright; the outer frame
            // has to be the rotated (transposed) size or every band reserves a
            // track-length of horizontal space and only a handful stay on screen.
            Slider(
                value: $band.gain,
                in: gainRange,
                step: 0.5
            )
            .frame(width: Self.trackLength, height: columnWidth)
            .rotationEffect(.degrees(-90), anchor: .center)
            .frame(width: columnWidth, height: Self.trackLength)
            .tint(gainColor)

            // Frequency label
            Text(band.frequencyLabel)
                .font(.system(size: isCompact ? 8 : 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Dot indicator for tap to toggle on/off
            Button {
                band.isEnabled.toggle()
            } label: {
                Circle()
                    .fill(band.isEnabled ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .buttonStyle(.plain)
            .help(band.isEnabled ? "Disable band" : "Enable band")

            Text("Off")
                .font(.system(size: 8))
                .foregroundStyle(band.isEnabled ? Color.clear : Color.secondary)
        }
        .frame(width: columnWidth)
        .contextMenu {
            Button("Reset Gain") { band.gain = 0 }
            Button(band.isEnabled ? "Disable" : "Enable") { band.isEnabled.toggle() }
        }
    }

    private var gainColor: Color {
        if band.gain > 3 { return .green }
        if band.gain < -3 { return .orange }
        return .primary
    }
}

// MARK: - Editable Band Value

struct BandEditable {
    var gain: Double
    var frequency: Double
    var bandwidth: Double
    var filterType: EQBand.FilterType
    var isEnabled: Bool

    var frequencyLabel: String {
        if frequency >= 1000 {
            return String(format: "%.1fk", frequency / 1000)
        }
        return String(format: "%.0f", frequency)
    }
}