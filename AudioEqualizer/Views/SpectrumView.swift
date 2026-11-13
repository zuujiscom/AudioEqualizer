// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The response graph: the live spectrum, with the EQ's combined curve drawn
/// over it on the same log-frequency axis and one handle per band. Dragging
/// across the graph paints the curve — each band takes the height of the
/// pointer as it passes — and a double-click returns a band to 0 dB.
///
/// Keeps its historical name; it grew from the spectrum panel.
struct SpectrumView: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var meters: MeterState
    /// The ± dB span of the graph. Widens by itself when a band exceeds it.
    @AppStorage("eqGraphRange") private var rangeSetting = 12.0
    @State private var smoother = SpectrumSmoother()
    @State private var hover: CGPoint?
    @State private var isDragging = false

    private var range: Double {
        let peak = engine.bands.map { abs($0.gain) }.max() ?? 0
        return peak > 12 ? 24 : rangeSetting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionTitle(text: "Response", systemImage: "waveform.path.ecg")

                Text("Drag to draw the curve · double-click a band to reset it")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)

                Spacer(minLength: 8)

                LevelMeter(level: meters.snapshot.level)
                    .frame(width: 96, height: 6)
                    .help("Output level")

                if engine.isRunning {
                    infoChip(meters.snapshot.latencyMs > 0 ? String(format: "%.1f ms", meters.snapshot.latencyMs) : "— ms")
                        .frame(minWidth: 44, alignment: .trailing)
                    infoChip(engine.outputFormat)
                }

                Button {
                    rangeSetting = rangeSetting > 12 ? 12 : 24
                } label: {
                    Text("±\(Int(range)) dB")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Switch the graph between ±12 dB and ±24 dB")
            }

            GeometryReader { geo in
                let layout = GraphLayout(size: geo.size, range: range)
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.isRunning)) { timeline in
                    Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                        render(&context, layout: layout, date: timeline.date)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            isDragging = true
                            hover = drag.location
                            paint(at: drag.location, layout: layout)
                        }
                        .onEnded { _ in isDragging = false }
                )
                .simultaneousGesture(
                    SpatialTapGesture(count: 2).onEnded { tap in
                        if let index = nearestBand(to: tap.location.x, layout: layout) {
                            engine.setGain(0, forBand: index)
                        }
                    }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hover = point
                    case .ended: if !isDragging { hover = nil }
                    }
                }
            }
            .frame(minHeight: 190, idealHeight: 250, maxHeight: .infinity)
            .background(Theme.well)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        }
        .card()
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
    }

    // MARK: Editing

    private func nearestBand(to x: CGFloat, layout: GraphLayout) -> Int? {
        guard !engine.bands.isEmpty else { return nil }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, band) in engine.bands.enumerated() {
            let distance = abs(layout.x(band.frequency) - x)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private func paint(at point: CGPoint, layout: GraphLayout) {
        guard let index = nearestBand(to: point.x, layout: layout) else { return }
        let gain = (layout.gain(point.y) * 2).rounded() / 2
        let clamped = min(max(gain, AudioEngine.minBandGain), AudioEngine.maxBandGain)
        if engine.bands[index].gain != clamped {
            engine.setGain(clamped, forBand: index)
        }
    }

    // MARK: Drawing

    private func render(_ context: inout GraphicsContext, layout: GraphLayout, date: Date) {
        let plot = layout.plot
        drawGrid(&context, layout: layout)

        smoother.step(toward: meters.snapshot.spectrum, at: date, live: engine.isRunning)
        if engine.isRunning {
            drawSpectrum(&context, plot: plot)
        }
        drawCurve(&context, layout: layout)
        drawHandles(&context, layout: layout)

        if engine.isBypassed {
            context.draw(
                Text("BYPASSED").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.amber),
                at: CGPoint(x: plot.maxX - 6, y: plot.minY + 6), anchor: .topTrailing
            )
        } else if !engine.isRunning {
            context.draw(
                Text("ENGINE OFF").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.3)),
                at: CGPoint(x: plot.maxX - 6, y: plot.minY + 6), anchor: .topTrailing
            )
        }
    }

    private func drawGrid(_ context: inout GraphicsContext, layout: GraphLayout) {
        let plot = layout.plot
        let labelled: [(Double, String)] = [
            (20, "20"), (50, "50"), (100, "100"), (200, "200"), (500, "500"),
            (1_000, "1k"), (2_000, "2k"), (5_000, "5k"), (10_000, "10k"), (20_000, "20k")
        ]
        let minor: [Double] = [30, 40, 60, 70, 80, 90, 300, 400, 600, 700, 800, 900,
                               3_000, 4_000, 6_000, 7_000, 8_000, 9_000]

        var minorPath = Path()
        for frequency in minor {
            let x = layout.x(frequency)
            minorPath.move(to: CGPoint(x: x, y: plot.minY))
            minorPath.addLine(to: CGPoint(x: x, y: plot.maxY))
        }
        context.stroke(minorPath, with: .color(.white.opacity(0.025)), lineWidth: 1)

        var majorPath = Path()
        for (frequency, label) in labelled {
            let x = layout.x(frequency)
            majorPath.move(to: CGPoint(x: x, y: plot.minY))
            majorPath.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.draw(
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.38)),
                at: CGPoint(x: x, y: plot.maxY + 4), anchor: .top
            )
        }

        let step = layout.range / 2
        for multiple in -2...2 where multiple != 0 {
            let db = Double(multiple) * step
            let y = layout.y(db)
            majorPath.move(to: CGPoint(x: plot.minX, y: y))
            majorPath.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.draw(
                Text(String(format: "%+.0f", db)).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38)),
                at: CGPoint(x: plot.minX - 5, y: y), anchor: .trailing
            )
        }
        context.stroke(majorPath, with: .color(.white.opacity(0.06)), lineWidth: 1)

        var zero = Path()
        zero.move(to: CGPoint(x: plot.minX, y: layout.y(0)))
        zero.addLine(to: CGPoint(x: plot.maxX, y: layout.y(0)))
        context.stroke(zero, with: .color(.white.opacity(0.20)), lineWidth: 1)
        context.draw(
            Text("0").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.55)),
            at: CGPoint(x: plot.minX - 5, y: layout.y(0)), anchor: .trailing
        )
    }

    /// A smooth line through `values`, one point per spectrum bin.
    private func line(through values: [Float], plot: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        func point(_ index: Int) -> CGPoint {
            let x = plot.minX + (CGFloat(index) + 0.5) / CGFloat(values.count) * plot.width
            let y = plot.maxY - CGFloat(min(1, max(0, values[index]))) * plot.height * 0.94
            return CGPoint(x: x, y: y)
        }
        let first = point(0)
        path.move(to: CGPoint(x: plot.minX, y: first.y))
        path.addLine(to: first)
        for index in 1..<values.count {
            let previous = point(index - 1)
            let current = point(index)
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if index == values.count - 1 {
                path.addQuadCurve(to: current, control: current)
            }
        }
        path.addLine(to: CGPoint(x: plot.maxX, y: point(values.count - 1).y))
        return path
    }

    private func drawSpectrum(_ context: inout GraphicsContext, plot: CGRect) {
        let top = line(through: smoother.values, plot: plot)
        var area = top
        area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        area.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        area.closeSubpath()

        let across = GraphicsContext.Shading.linearGradient(
            Gradient(colors: Theme.signalColors),
            startPoint: CGPoint(x: plot.minX, y: 0), endPoint: CGPoint(x: plot.maxX, y: 0)
        )
        var fill = context
        fill.opacity = 0.42
        fill.fill(area, with: across)
        // Fade the fill out toward the floor so the curve stays readable.
        context.fill(area, with: .linearGradient(
            Gradient(colors: [Theme.well.opacity(0), Theme.well.opacity(0.9)]),
            startPoint: CGPoint(x: 0, y: plot.minY + plot.height * 0.35),
            endPoint: CGPoint(x: 0, y: plot.maxY)
        ))

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.opacity = 0.8
            layer.stroke(top, with: across, lineWidth: 3)
        }
        context.stroke(top, with: across, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

        context.stroke(line(through: smoother.peaks, plot: plot),
                       with: .color(.white.opacity(0.26)), lineWidth: 1)
    }

    private func drawCurve(_ context: inout GraphicsContext, layout: GraphLayout) {
        let plot = layout.plot
        let rate = engine.sampleRate
        let sections = EQResponse.sections(for: engine.bands, sampleRate: rate)
        let samples = max(32, Int(plot.width / 3))

        var curve = Path()
        for index in 0...samples {
            let t = Double(index) / Double(samples)
            let frequency = GraphLayout.minFrequency * pow(GraphLayout.maxFrequency / GraphLayout.minFrequency, t)
            let db = EQResponse.decibels(sections, at: frequency, sampleRate: rate)
            let point = CGPoint(x: plot.minX + CGFloat(t) * plot.width,
                                y: min(plot.maxY, max(plot.minY, layout.y(db))))
            if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
        }

        if engine.isBypassed {
            context.stroke(curve, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            return
        }

        let zeroY = layout.y(0)
        var area = curve
        area.addLine(to: CGPoint(x: plot.maxX, y: zeroY))
        area.addLine(to: CGPoint(x: plot.minX, y: zeroY))
        area.closeSubpath()

        var boosts = context
        boosts.clip(to: Path(CGRect(x: plot.minX, y: plot.minY, width: plot.width, height: zeroY - plot.minY)))
        boosts.fill(area, with: .linearGradient(
            Gradient(colors: [Theme.mint.opacity(0.30), Theme.mint.opacity(0.04)]),
            startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: zeroY)
        ))
        var cuts = context
        cuts.clip(to: Path(CGRect(x: plot.minX, y: zeroY, width: plot.width, height: plot.maxY - zeroY)))
        cuts.fill(area, with: .linearGradient(
            Gradient(colors: [Theme.amber.opacity(0.04), Theme.amber.opacity(0.28)]),
            startPoint: CGPoint(x: 0, y: zeroY), endPoint: CGPoint(x: 0, y: plot.maxY)
        ))

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.opacity = 0.55
            layer.stroke(curve, with: .color(Theme.mint), lineWidth: 4)
        }
        context.stroke(curve, with: .color(.white.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func drawHandles(_ context: inout GraphicsContext, layout: GraphLayout) {
        let plot = layout.plot
        let bands = engine.bands
        let radius: CGFloat = bands.count > 20 ? 3 : (bands.count > 12 ? 4 : 5)

        var focused: Int?
        if let hover, plot.insetBy(dx: -8, dy: -8).contains(hover) {
            focused = nearestBand(to: hover.x, layout: layout)
        }

        for (index, band) in bands.enumerated() {
            let centre = CGPoint(x: layout.x(band.frequency),
                                 y: min(plot.maxY, max(plot.minY, layout.y(band.gain))))
            let isFocused = index == focused
            let r = isFocused ? radius + 2.5 : radius
            let circle = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            let tint = band.isEnabled ? Theme.gainColor(band.gain) : Color.white.opacity(0.25)

            if isFocused {
                var guide = Path()
                guide.move(to: CGPoint(x: centre.x, y: plot.minY))
                guide.addLine(to: CGPoint(x: centre.x, y: plot.maxY))
                context.stroke(guide, with: .color(.white.opacity(0.14)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                let halo = Path(ellipseIn: CGRect(x: centre.x - r - 5, y: centre.y - r - 5,
                                                  width: (r + 5) * 2, height: (r + 5) * 2))
                context.fill(halo, with: .color(tint.opacity(0.22)))
            }

            context.fill(circle, with: .color(band.isEnabled ? tint : Theme.well))
            context.stroke(circle, with: .color(band.isEnabled ? Theme.well.opacity(0.9) : tint),
                           lineWidth: 1.5)
        }

        // The readout for the band under the pointer.
        guard let focused, focused < bands.count else { return }
        let band = bands[focused]
        let frequency = band.frequency >= 1_000
            ? String(format: "%.1f kHz", band.frequency / 1_000)
            : String(format: "%.0f Hz", band.frequency)
        let label = Text("\(frequency)   \(String(format: "%+.1f dB", band.gain))")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
        let resolved = context.resolve(label)
        let textSize = resolved.measure(in: CGSize(width: 240, height: 40))
        let boxSize = CGSize(width: textSize.width + 16, height: textSize.height + 10)
        let nodeX = layout.x(band.frequency)
        let nodeY = min(plot.maxY, max(plot.minY, layout.y(band.gain)))
        var origin = CGPoint(x: nodeX - boxSize.width / 2, y: nodeY - boxSize.height - 14)
        if origin.y < plot.minY + 2 { origin.y = nodeY + 14 }
        origin.x = min(max(origin.x, plot.minX + 2), plot.maxX - boxSize.width - 2)
        let box = Path(roundedRect: CGRect(origin: origin, size: boxSize), cornerRadius: 7)
        context.fill(box, with: .color(Color(red: 0.10, green: 0.11, blue: 0.17).opacity(0.96)))
        context.stroke(box, with: .color(.white.opacity(0.16)), lineWidth: 1)
        context.draw(resolved, at: CGPoint(x: origin.x + boxSize.width / 2, y: origin.y + boxSize.height / 2),
                     anchor: .center)
    }
}

// MARK: - Layout

/// Maps frequency and gain onto the graph. Frequency is logarithmic from
/// 20 Hz to 20 kHz — the same span and spacing as the analyzer's 64 bins, so
/// bin *i* of the spectrum lands at fraction *(i + 0.5) / 64* of the width.
private struct GraphLayout {
    static let minFrequency = 20.0
    static let maxFrequency = 20_000.0

    let plot: CGRect
    let range: Double

    init(size: CGSize, range: Double) {
        plot = CGRect(x: 34, y: 10, width: max(10, size.width - 46), height: max(10, size.height - 32))
        self.range = range
    }

    func x(_ frequency: Double) -> CGFloat {
        let clamped = min(max(frequency, Self.minFrequency), Self.maxFrequency)
        let t = log10(clamped / Self.minFrequency) / log10(Self.maxFrequency / Self.minFrequency)
        return plot.minX + CGFloat(t) * plot.width
    }

    func y(_ decibels: Double) -> CGFloat {
        plot.midY - CGFloat(decibels / range) * plot.height / 2
    }

    func gain(_ y: CGFloat) -> Double {
        let clampedY = min(max(y, plot.minY), plot.maxY)
        return Double((plot.midY - clampedY) / (plot.height / 2)) * range
    }
}

// MARK: - Smoothing

/// Eases the drawn spectrum toward the 20 Hz meter snapshots so the graph
/// moves at display rate, and tracks a slowly falling peak for each bin.
/// A class rather than `@State` values: it is advanced from inside the
/// `Canvas` renderer, where view state cannot be written. Each view that
/// draws the spectrum owns its own.
final class SpectrumSmoother {
    private(set) var values = [Float](repeating: 0, count: 64)
    private(set) var peaks = [Float](repeating: 0, count: 64)
    private var last: Date?

    func step(toward target: [Float], at date: Date, live: Bool) {
        guard live, target.count == values.count else {
            // Stopped: nothing to ease toward, and no timeline to ease on.
            for index in values.indices {
                values[index] = 0
                peaks[index] = 0
            }
            last = nil
            return
        }
        let dt = Float(min(0.1, max(0, date.timeIntervalSince(last ?? date))))
        last = date
        guard dt > 0 else { return }

        let attack = 1 - exp(-dt * 32)
        let release = 1 - exp(-dt * 9)
        for index in values.indices {
            let goal = target[index]
            values[index] += (goal - values[index]) * (goal > values[index] ? attack : release)
            peaks[index] = max(values[index], peaks[index] - dt * 0.22)
        }
    }
}

// MARK: - Level meter

/// Output level as a slim bar: mint through amber to red at the top.
struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                LinearGradient(
                    stops: [
                        .init(color: Theme.mint, location: 0),
                        .init(color: Theme.mint, location: 0.6),
                        .init(color: Theme.amber, location: 0.85),
                        .init(color: Theme.red, location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .mask(alignment: .leading) {
                    Rectangle().frame(width: geo.size.width * CGFloat(min(1, max(0, level))))
                }
                .animation(.linear(duration: 0.07), value: level)
            }
            .clipShape(Capsule())
        }
    }
}
