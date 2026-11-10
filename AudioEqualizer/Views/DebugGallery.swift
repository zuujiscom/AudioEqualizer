// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit
import Metal
import SwiftUI

/// A development aid, compiled into Debug builds only. Launching the app with
/// `AEQ_GALLERY=/some/folder` renders every visualizer preset offscreen from a
/// synthetic signal, writes contact sheets there, and quits — without ever
/// starting the audio engine, so it is safe to run while the real app is the
/// machine's audio path.
///
/// It also checks the rule that the visualizer is driven only by audio: after
/// the signal stops, two consecutive frames of every preset must be identical.
@MainActor
enum DebugGallery {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["AEQ_GALLERY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static let tile = (width: 480, height: 300)

    /// A stand-in for music: a kick on every beat, a moving mid peak, hats.
    static func syntheticFrame(at t: Double) -> VisualizerFrame {
        let beat = (t * 2).truncatingRemainder(dividingBy: 1)
        let kick = Float(exp(-beat * 8))
        let hat = Float(exp(-(t * 4).truncatingRemainder(dividingBy: 1) * 14))

        var spectrum = [Float](repeating: 0, count: 64)
        for i in 0..<64 {
            let x = Float(i) / 63
            var v = 0.42 * pow(1 - x, 1.3)
            v += kick * 0.55 * exp(-x * 11)
            let sweep = Float(sin(t * 1.3 + Double(x) * 9))
            v += 0.26 * sweep * sweep * (1 - x * 0.5)
            let peak = 0.5 + 0.3 * Float(sin(t * 0.7))
            v += 0.35 * exp(-pow((x - peak) * 9, 2))
            v += hat * 0.3 * max(0, x - 0.65)
            spectrum[i] = max(0, min(1, v))
        }

        var waveform = [Float](repeating: 0, count: 256)
        for j in 0..<256 {
            let x = Double(j) / 256
            let low = sin(2 * .pi * (3 + 2 * sin(t)) * x + t * 3) * Double(0.25 + kick * 0.45)
            let high = sin(2 * .pi * 13 * x + t * 7) * 0.14
            waveform[j] = Float(low + high)
        }
        return VisualizerFrame(waveform: waveform, spectrum: spectrum,
                               bass: min(1, 0.12 + kick * 0.88), level: 0.32 + kick * 0.3)
    }

    private static let silence = VisualizerFrame(
        waveform: [Float](repeating: 0, count: 256),
        spectrum: [Float](repeating: 0, count: 64), bass: 0, level: 0
    )

    static func renderVisualizer(to directory: URL) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var presets = VisualizerMode.selectable.map { VisualizerPreset.standard(for: $0) }
        presets += VisualizerPreset.rotation
        presets += (0..<9).map { _ in VisualizerPreset.remix() }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: tile.width, height: tile.height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let output = device.makeTexture(descriptor: desc) else { return }

        func frameBytes() -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: tile.width * tile.height * 4)
            output.getBytes(&bytes, bytesPerRow: tile.width * 4,
                            from: MTLRegionMake2D(0, 0, tile.width, tile.height), mipmapLevel: 0)
            return bytes
        }

        var tiles: [(String, CGImage)] = []
        var report: [String] = []

        for preset in presets {
            guard let renderer = VisualizerRenderer(device: device, pixelFormat: .bgra8Unorm) else {
                report.append("FAILED to build renderer")
                break
            }
            renderer.presetOverride = preset

            func render(_ frame: VisualizerFrame) {
                guard let commandBuffer = queue.makeCommandBuffer() else { return }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = output
                pass.colorAttachments[0].storeAction = .store
                _ = renderer.encode(frame: frame, size: CGSize(width: tile.width, height: tile.height),
                                    present: pass, commandBuffer: commandBuffer)
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
            }

            for i in 0..<200 { render(syntheticFrame(at: Double(i) / 60)) }
            let lit = frameBytes()
            if let image = cgImage(from: lit) { tiles.append((preset.name, image)) }

            // Silence: let everything settle, then demand a frozen picture.
            for _ in 0..<600 { render(silence) }
            let first = frameBytes()
            render(silence)
            let second = frameBytes()
            let mean = lit.reduce(0) { $0 + Int($1) } / lit.count
            report.append("\(first == second ? "static" : "MOVES ")  mean=\(mean)  \(preset.mode.rawValue) / \(preset.name)")
        }

        // The shuffle itself: a short dwell, and every switch it makes.
        if let renderer = VisualizerRenderer(device: device, pixelFormat: .bgra8Unorm) {
            var names: [String] = []
            renderer.onPresetChange = { names.append($0) }
            renderer.dwell = 0.5
            renderer.mode = .auto
            for i in 0..<1500 {
                guard let commandBuffer = queue.makeCommandBuffer() else { break }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = output
                pass.colorAttachments[0].storeAction = .store
                _ = renderer.encode(frame: syntheticFrame(at: Double(i) / 60),
                                    size: CGSize(width: tile.width, height: tile.height),
                                    present: pass, commandBuffer: commandBuffer)
                commandBuffer.commit()
            }
            let before = names.count
            renderer.previousPreset()
            renderer.nextPreset()
            report.append("shuffle: \(before) switches in 25 s; back/forward gave \(names.suffix(2))")
            report.append("shuffle order: " + names.prefix(before).joined(separator: " | "))
        }

        let perSheet = 12
        var sheet = 0
        var start = 0
        while start < tiles.count {
            let slice = Array(tiles[start..<min(tiles.count, start + perSheet)])
            write(sheet: slice, to: directory.appendingPathComponent(String(format: "sheet-%02d.png", sheet)))
            start += perSheet
            sheet += 1
        }
        try? report.joined(separator: "\n").write(
            to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8
        )
    }

    private static func cgImage(from bytes: [UInt8]) -> CGImage? {
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: tile.width, height: tile.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: tile.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func write(sheet tiles: [(String, CGImage)], to url: URL) {
        let columns = 4
        let rows = Int(ceil(Double(tiles.count) / Double(columns)))
        let label = 22
        let size = NSSize(width: columns * tile.width, height: rows * (tile.height + label))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, entry) in tiles.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = CGFloat(column * tile.width)
            let y = size.height - CGFloat((row + 1) * (tile.height + label))
            context.cgContext.draw(entry.1, in: CGRect(x: x, y: y + CGFloat(label),
                                                       width: CGFloat(tile.width), height: CGFloat(tile.height)))
            NSString(string: entry.0).draw(
                at: NSPoint(x: x + 6, y: y + 4),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                 .foregroundColor: NSColor.white]
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Captures a window's content without needing screen-recording access.
    static func snapshot(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Runs the gallery and quits. Called before the engine is given its
    /// profile store, so nothing here can reach the user's saved profiles.
    static func run(engine: AudioEngine, directory: URL) {
        Task { @MainActor in
            if ProcessInfo.processInfo.environment["AEQ_GALLERY_UI_ONLY"] == nil {
                renderVisualizer(to: directory)
            }

            // Dress the main window as if it were running, for a look at the UI.
            let gains: [Double] = [5, 4, 2.5, 0, -2, -1, 1.5, 3.5, 4.5, 3]
            for index in engine.bands.indices where index < gains.count {
                engine.bands[index].gain = gains[index]
            }
            engine.isRunning = true
            let fake = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in
                    engine.meters.snapshot = MeterSnapshot(
                        spectrum: syntheticFrame(at: Date().timeIntervalSinceReferenceDate).spectrum,
                        level: 0.55, latencyMs: 10.7
                    )
                }
            }
            try? await Task.sleep(for: .seconds(1.5))
            if let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) {
                snapshot(window, to: directory.appendingPathComponent("main-window.png"))
                try? "\(window.windowNumber)".write(
                    to: directory.appendingPathComponent("window-id.txt"), atomically: true, encoding: .utf8
                )
            }
            if ProcessInfo.processInfo.environment["AEQ_GALLERY_HOLD"] != nil { return }
            fake.invalidate()
            engine.isRunning = false
            exit(0)
        }
    }
}
#endif
