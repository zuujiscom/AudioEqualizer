// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct BandControlsView: View {
    @EnvironmentObject private var engine: AudioEngine
    @State private var showBandDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionTitle(text: "Equalizer", systemImage: "slider.vertical.3")
                Spacer()

                Button {
                    withAnimation(.spring(duration: 0.3)) { engine.resetToFlat() }
                } label: {
                    Label("Flat", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(isFlat ? 0.35 : 0.85))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isFlat)
                .help("Set every band to 0 dB  (⇧⌘R)")

                Picker("Bands", selection: bandCountSelection) {
                    Text("10").tag(10)
                    Text("15").tag(15)
                    Text("31").tag(31)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 132)
                .help("Number of bands")

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showBandDetails.toggle() }
                } label: {
                    Image(systemName: "tablecells")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(showBandDetails ? Theme.cyan : Color.white.opacity(0.6))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show every band's frequency, gain, Q and type")
            }

            amplificationRow

            bandRow

            if showBandDetails {
                bandDetailsGrid
            }
        }
        .card()
    }

    private var isFlat: Bool {
        engine.bands.allSatisfy { $0.gain == 0 }
    }

    /// The bands are laid out to fit the panel: columns shrink toward
    /// `minColumnWidth` as the band count grows, and only fall back to
    /// horizontal scrolling once even the narrowest column no longer fits.
    /// A fixed column width made 31-band mode several screens wide.
    private static let columnSpacing: CGFloat = 2
    private static let minColumnWidth: CGFloat = 20
    private static let maxColumnWidth: CGFloat = 120

    private var bandRow: some View {
        GeometryReader { geo in
            let count = max(1, engine.bands.count)
            let gaps = Self.columnSpacing * CGFloat(count - 1)
            let ideal = (geo.size.width - gaps) / CGFloat(count)
            let column = min(Self.maxColumnWidth, max(Self.minColumnWidth, ideal))
            let fits = column * CGFloat(count) + gaps <= geo.size.width + 0.5
            let track = max(90, geo.size.height - BandSlider.labelsHeight)

            let row = HStack(alignment: .bottom, spacing: Self.columnSpacing) {
                ForEach(Array(engine.bands.enumerated()), id: \.element.id) { index, _ in
                    BandSlider(
                        band: binding(forIndex: index),
                        index: index,
                        columnWidth: column,
                        trackLength: track
                    )
                }
            }

            if fits {
                row
                    .background(alignment: .topLeading) {
                        BandLevelBackdrop(
                            frequencies: engine.bands.map(\.frequency),
                            column: column, spacing: Self.columnSpacing, trackLength: track
                        )
                    }
                    .frame(width: geo.size.width, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: true) { row }
            }
        }
        .frame(minHeight: BandSlider.minRowHeight, idealHeight: BandSlider.minRowHeight, maxHeight: 360)
        .padding(.vertical, 6)
    }

    private var amplificationRow: some View {
        HStack(spacing: 10) {
            Text("PREAMP")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.45))
            Slider(value: $engine.masterGain, in: 0.25...AudioEngine.maxGain, step: 0.05)
                .tint(engine.amplificationDB > 12 ? Theme.amber : Theme.mint)
            Text(String(format: "%+0.1f dB", engine.amplificationDB))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.gainColor(engine.amplificationDB))
                .frame(width: 64, alignment: .trailing)
            Text(String(format: "×%.2f", engine.masterGain))
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 44, alignment: .trailing)
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    engine.masterGain = 1.0
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(engine.masterGain == 1 ? 0.25 : 0.75))
            }
            .buttonStyle(.plain)
            .disabled(engine.masterGain == 1)
            .help("Reset the preamp to 0 dB")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.04)))
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

    /// Track length of the vertical slider; grows with the window.
    let trackLength: CGFloat

    /// Height of everything in a column that is not the track.
    static let labelsHeight: CGFloat = 56
    /// Distance from the top of a column to the top of its track.
    static let trackTop: CGFloat = 15
    static let minRowHeight: CGFloat = 130 + labelsHeight

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
                .foregroundStyle(band.isEnabled && band.gain != 0 ? gainColor : Color.white.opacity(0.28))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // A native vertical slider rather than a rotated `Slider`: rotation
            // is visual only, so the AppKit control underneath kept tracking
            // the mouse horizontally in unrotated coordinates and the knob did
            // not follow a vertical drag.
            VerticalGainSlider(
                value: $band.gain,
                range: gainRange,
                step: 0.5,
                tint: gainColor
            )
            .frame(width: columnWidth, height: trackLength)
            .opacity(band.isEnabled ? 1 : 0.35)

            // Frequency label
            Text(band.frequencyLabel)
                .font(.system(size: isCompact ? 8 : 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Dot indicator for tap to toggle on/off
            Button {
                band.isEnabled.toggle()
            } label: {
                Circle()
                    .fill(band.isEnabled ? Theme.cyan : Color.white.opacity(0.18))
                    .frame(width: 7, height: 7)
                    .shadow(color: band.isEnabled ? Theme.cyan.opacity(0.7) : .clear, radius: 3)
                    .frame(width: 16, height: 12)
                    .contentShape(Rectangle())
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

    private var gainColor: Color { Theme.gainColor(band.gain) }
}

// MARK: - Live level behind the faders

/// A soft column of light behind each fader, as tall as the signal at that
/// band's frequency — so you can see what a fader is acting on.
///
/// Its own view, and one `Canvas`, on purpose: it follows the meters, and the
/// faders must not. Hanging this off `BandSlider` would invalidate every
/// slider twenty times a second.
struct BandLevelBackdrop: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var meters: MeterState
    @State private var smoother = SpectrumSmoother()

    let frequencies: [Double]
    let column: CGFloat
    let spacing: CGFloat
    let trackLength: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.isRunning)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                smoother.step(toward: meters.snapshot.spectrum, at: timeline.date, live: engine.isRunning)
                guard engine.isRunning, !frequencies.isEmpty else { return }

                let values = smoother.values
                let bottom = BandSlider.trackTop + trackLength - 7
                let reach = trackLength - 14
                let width = min(column - 2, 18)
                for (index, frequency) in frequencies.enumerated() {
                    let t = log10(min(max(frequency, 20), 20_000) / 20) / 3
                    let bin = min(values.count - 1, max(0, Int(t * Double(values.count))))
                    let level = CGFloat(min(1, max(0, values[bin])))
                    guard level > 0.01 else { continue }

                    let centre = CGFloat(index) * (column + spacing) + column / 2
                    let height = level * reach
                    let rect = CGRect(x: centre - width / 2, y: bottom - height, width: width, height: height)
                    let tint = Self.tint(at: Double(index) / Double(max(1, frequencies.count - 1)))
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .linearGradient(
                            Gradient(colors: [tint.opacity(0.34), tint.opacity(0.03)]),
                            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)
                        )
                    )
                    context.fill(
                        Path(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: width, height: 1.5),
                             cornerRadius: 0.75),
                        with: .color(tint.opacity(0.75))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The signal gradient, sampled: cyan at the low end, pink at the top.
    private static func tint(at t: Double) -> Color {
        t < 0.5 ? Theme.cyan.mix(with: Theme.violet, by: t * 2)
                : Theme.violet.mix(with: Theme.pink, by: (t - 0.5) * 2)
    }
}

// MARK: - Vertical Gain Slider

/// A vertical slider whose knob follows the pointer's vertical position and
/// responds to the scroll wheel while the pointer is over it. The fill runs
/// from the 0 dB line to the knob, so boosts and cuts read at a glance.
struct VerticalGainSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    /// The cap's height; also the travel lost at each end of the track.
    private static let knobSize: CGFloat = 14
    private static let trackWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let knobY = yPosition(for: value, height: geo.size.height)
            let zeroY = yPosition(for: min(max(0, range.lowerBound), range.upperBound), height: geo.size.height)

            let capWidth = min(22, max(12, geo.size.width - 6))
            let active = value != 0

            ZStack {
                // Scale marks at ±12 dB, so a glance places the cap.
                ForEach([-18.0, -12.0, -6.0, 6.0, 12.0, 18.0], id: \.self) { mark in
                    Rectangle()
                        .fill(Color.white.opacity(abs(mark) == 12 ? 0.16 : 0.08))
                        .frame(width: Self.trackWidth + (abs(mark) == 12 ? 6 : 3), height: 1)
                        .position(x: midX, y: yPosition(for: mark, height: geo.size.height))
                }

                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: Self.trackWidth, height: geo.size.height - Self.knobSize)
                    .position(x: midX, y: geo.size.height / 2)

                Rectangle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: Self.trackWidth + 8, height: 1)
                    .position(x: midX, y: zeroY)

                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.45)],
                                         startPoint: value >= 0 ? .top : .bottom,
                                         endPoint: value >= 0 ? .bottom : .top))
                    .frame(width: Self.trackWidth, height: abs(knobY - zeroY))
                    .position(x: midX, y: (knobY + zeroY) / 2)
                    .shadow(color: active ? tint.opacity(0.6) : .clear, radius: 4)

                // A fader cap: wide, short, with a centre line in the gain's colour.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.74)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        Rectangle()
                            .fill(active ? tint : Color.black.opacity(0.35))
                            .frame(height: 2)
                            .padding(.horizontal, 3)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.25)))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .frame(width: capWidth, height: Self.knobSize)
                    .position(x: midX, y: knobY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        set(self.value(forY: drag.location.y, height: geo.size.height))
                    }
            )
            // Runs after the drag has moved the cap to the click, so the
            // second click of a double-click lands on zero.
            .simultaneousGesture(TapGesture(count: 2).onEnded { set(0) })
        }
        .background(ScrollWheelReader { steps in
            set(value + Double(steps) * step)
        })
        .accessibilityElement()
        .accessibilityLabel("Gain")
        .accessibilityValue(String(format: "%+0.1f decibels", value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + 1)
            case .decrement: set(value - 1)
            @unknown default: break
            }
        }
    }

    /// Clamps and only writes on a real change, because every write re-applies
    /// the band to the EQ node.
    private func set(_ newValue: Double) {
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        if clamped != value { value = clamped }
    }

    /// The knob's centre stays inside the frame, so the usable track is the
    /// height minus one knob.
    private func yPosition(for value: Double, height: CGFloat) -> CGFloat {
        let usable = max(1, height - Self.knobSize)
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return Self.knobSize / 2 + usable * CGFloat(1 - fraction)
    }

    private func value(forY y: CGFloat, height: CGFloat) -> Double {
        let usable = max(1, height - Self.knobSize)
        let clampedY = min(max(y, Self.knobSize / 2), height - Self.knobSize / 2)
        let fraction = 1 - Double((clampedY - Self.knobSize / 2) / usable)
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        return (raw / step).rounded() * step
    }
}

// MARK: - Scroll Wheel

/// Reports vertical scroll-wheel movement over its bounds as whole steps,
/// positive for scrolling up. SwiftUI has no scroll-wheel event on macOS, so
/// this watches scroll events with a local monitor rather than joining the
/// responder chain: the view never takes a click, and horizontal scrolls pass
/// through to the band row's `ScrollView` in 31-band overflow mode.
private struct ScrollWheelReader: NSViewRepresentable {
    let onScroll: (Int) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class ScrollWheelView: NSView {
        var onScroll: ((Int) -> Void)?
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        /// Trackpad points of travel per step, so a swipe isn't a jump to ±24 dB.
        private static let pointsPerStep: CGFloat = 6

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.handle(event) else { return event }
                return nil
            }
        }

        deinit { removeMonitor() }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Returns true when the event was consumed.
        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window,
                  bounds.contains(convert(event.locationInWindow, from: nil)),
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
            else { return false }

            // Physical "up" raises the gain whatever the natural-scrolling setting.
            let deltaY = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            let steps: Int
            if event.hasPreciseScrollingDeltas {
                if event.phase == .began { accumulated = 0 }
                accumulated += deltaY
                steps = Int(accumulated / Self.pointsPerStep)
                accumulated -= CGFloat(steps) * Self.pointsPerStep
            } else {
                // One wheel notch is one step; fast spins arrive as larger deltas.
                steps = deltaY > 0 ? max(1, Int(deltaY.rounded())) : min(-1, Int(deltaY.rounded()))
            }
            if steps != 0 { onScroll?(steps) }
            return true
        }
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
