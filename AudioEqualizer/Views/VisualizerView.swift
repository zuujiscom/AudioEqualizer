// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import MetalKit
import simd

// MARK: - Modes

enum VisualizerMode: String, CaseIterable, Identifiable {
    /// Shuffles through every preset, switching on a beat.
    case auto = "Auto"
    /// An imported MilkDrop preset drives the warp; see `MilkdropLibrary`.
    case milkdrop = "MilkDrop"
    // Geometric
    case bars = "Bars"
    case mirror = "Mirror"
    case radial = "Radial"
    case tunnel = "Tunnel"
    case scope = "Scope"
    case lissajous = "Lissajous"
    case ribbon = "Ribbon"
    // Particles
    case bloom = "Bloom"
    case starfield = "Starfield"
    case matrix = "Matrix"
    // Replicator — one cell duplicated across a layout
    case burst = "Burst"
    case helix = "Spiral"
    case waveform = "Wave"
    case grid = "Grid"
    case scatter = "Scatter"
    case halo = "Halo"
    case pinwheel = "Pinwheel"
    case mosaic = "Mosaic"
    // Simulation — emitters driven by Motion-style forces
    case orbitals = "Orbitals"
    case swarm = "Swarm"
    case cascade = "Cascade"
    case maelstrom = "Maelstrom"
    case fireflies = "Fireflies"
    case fountain = "Fountain"
    // Shader — computed per pixel on the GPU
    case plasma = "Plasma"
    case kaleidoscope = "Kaleidoscope"
    case aurora = "Aurora"
    case nebula = "Nebula"
    case metaballs = "Metaballs"
    case warp = "Warp"
    case fractal = "Fractal"
    case cells = "Cells"
    case outrun = "Outrun"
    case ridgeline = "Ridgeline"
    case chrono = "Chrono"
    case orb = "Orb"
    case rays = "Rays"
    case hive = "Hive"
    case ink = "Ink"
    case laser = "Laser"
    case galaxy = "Galaxy"
    case sonar = "Sonar"
    case circuit = "Circuit"
    case skyline = "Skyline"
    case eclipse = "Eclipse"
    case strings = "Strings"

    var id: String { rawValue }

    /// Point-sprite modes draw additively; the rest draw opaque geometry.
    var isParticle: Bool {
        switch self {
        case .bloom, .starfield, .matrix: return true
        default: return forceSpec != nil
        }
    }

    /// Non-nil for replicator modes: the whole look comes from this spec.
    var replicatorSpec: ReplicatorSpec? {
        switch self {
        case .burst:
            return ReplicatorSpec(cell: .bar, layout: .burst, count: 128, spin: 0.09,
                                  size: 0.030, sequence: 1.4, sequenceOffset: 2.0, radius: 0.88)
        case .helix:
            return ReplicatorSpec(cell: .diamond, layout: .spiral, count: 260, spin: 0.20,
                                  size: 0.026, sequence: 1.1, sequenceOffset: 4.5, radius: 0.94)
        case .waveform:
            return ReplicatorSpec(cell: .shard, layout: .wave, count: 180, spin: 0.45,
                                  size: 0.030, sequence: 1.6, sequenceOffset: 3.0)
        case .grid:
            return ReplicatorSpec(cell: .quad, layout: .grid, count: 289, spin: 0,
                                  size: 0.048, sequence: 1.7, sequenceOffset: 1.4)
        case .scatter:
            return ReplicatorSpec(cell: .triangle, layout: .scatter, count: 220, spin: 0.04,
                                  size: 0.040, sequence: 1.5, sequenceOffset: 2.6)
        case .halo:
            return ReplicatorSpec(cell: .shard, layout: .ring, count: 112, spin: 0.12,
                                  size: 0.060, sequence: 1.6, sequenceOffset: 6.0, radius: 0.58)
        case .pinwheel:
            return ReplicatorSpec(cell: .bar, layout: .spiral, count: 220, spin: -0.30,
                                  size: 0.034, sequence: 1.3, sequenceOffset: 8.0, radius: 0.96)
        case .mosaic:
            return ReplicatorSpec(cell: .diamond, layout: .grid, count: 400, spin: 0,
                                  size: 0.019, sequence: 1.9, sequenceOffset: 5.0)
        default:
            return nil
        }
    }

    /// Non-nil for simulation modes: an emitter plus the forces acting on it.
    var forceSpec: ForceField? {
        switch self {
        case .orbitals:
            return ForceField(vortex: 0.30, orbit: 0.55, drag: 0.010,
                              emitLayout: .ring, emitRadius: 0.5, rate: 9, lifetime: 0.004)
        case .swarm:
            return ForceField(attractor: 0.75, repel: 0.02, drag: 0.028, randomMotion: 0.55,
                              emitLayout: .scatter, emitRadius: 0.9, rate: 12, lifetime: 0.005)
        case .cascade:
            return ForceField(gravity: 0.5, wind: SIMD2(0.1, 0), drag: 0.012, randomMotion: 0.12,
                              emitLayout: .wave, emitRadius: 0.95, rate: 16, lifetime: 0.005)
        case .maelstrom:
            return ForceField(vortex: 0.55, attractor: 0.45, drag: 0.016,
                              emitLayout: .ring, emitRadius: 0.95, rate: 15, lifetime: 0.004)
        case .fireflies:
            return ForceField(orbit: 0.08, drag: 0.060, randomMotion: 1.3,
                              emitLayout: .scatter, emitRadius: 0.95, rate: 8, lifetime: 0.006)
        case .fountain:
            return ForceField(repel: 0.045, gravity: 0.40, drag: 0.010, randomMotion: 0.10,
                              emitLayout: .ring, emitRadius: 0.07, rate: 15, lifetime: 0.005)
        default:
            return nil
        }
    }

    /// Full-screen fragment-shader modes: no CPU geometry at all.
    var isProcedural: Bool { proceduralIndex != nil }

    /// The `case` this mode dispatches to in `f_procedural`.
    var proceduralIndex: Int32? {
        switch self {
        case .plasma: return 0
        case .kaleidoscope: return 1
        case .aurora: return 2
        case .nebula: return 3
        case .metaballs: return 4
        case .warp: return 5
        case .fractal: return 6
        case .cells: return 7
        case .outrun: return 8
        case .ridgeline: return 9
        case .chrono: return 10
        case .orb: return 11
        case .rays: return 12
        case .hive: return 13
        case .ink: return 14
        case .laser: return 15
        case .galaxy: return 16
        case .sonar: return 17
        case .circuit: return 18
        case .skyline: return 19
        case .eclipse: return 20
        case .strings: return 21
        default: return nil
        }
    }

    /// Shader modes that are light on black, and so read better added onto
    /// the feedback trails than laid over them.
    var prefersAdditive: Bool {
        switch self {
        case .rays, .laser, .eclipse, .strings, .sonar, .circuit, .galaxy: return true
        default: return false
        }
    }

    /// Shader modes that paint a whole scene; feedback behind them is wasted.
    var isScene: Bool {
        switch self {
        case .outrun, .ridgeline, .skyline: return true
        default: return false
        }
    }

    /// ⌘⌥1…⌘⌥9 then ⌘⌥0 for the first ten; the rest are click-only.
    var shortcut: KeyEquivalent? {
        guard let index = Self.allCases.firstIndex(of: self) else { return nil }
        let digits: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        return index < digits.count ? digits[index] : nil
    }

    var family: String {
        if self == .auto || self == .milkdrop { return "Auto" }
        if isProcedural { return "Shader" }
        if replicatorSpec != nil { return "Replicator" }
        if forceSpec != nil { return "Simulation" }
        return isParticle ? "Particles" : "Geometric"
    }

    /// Shared with `VisualizerWindow`'s `@AppStorage`, so picking a mode from
    /// the menu moves an already-open window too.
    static let storageKey = "visualizerMode"

    static var groups: [VisualizerModeGroup] {
        ["Geometric", "Replicator", "Simulation", "Particles", "Shader"].map { family in
            VisualizerModeGroup(id: family, modes: allCases.filter { $0.family == family })
        }
    }

    /// Everything that can be picked by hand or by the shuffle.
    static let selectable: [VisualizerMode] = allCases.filter { $0 != .auto && $0 != .milkdrop }
}

// MARK: - Motion-style composition

/// What is drawn at each element position. Everything is triangles so one
/// pipeline covers every cell.
enum VisualizerCell {
    case quad, bar, triangle, diamond, shard
}

/// Where copies are placed — Motion's replicator shapes.
enum ReplicatorLayout {
    case burst, spiral, wave, grid, scatter, ring
}

/// One cell duplicated across a layout. Unlike an emitter, elements here have
/// no birth or death: they are placed, and the spectrum drives their size and
/// colour. `sequenceOffset` is Motion's Sequence Replicator idea — a per-element
/// phase offset, so a wave of change travels through the pattern instead of
/// every element pulsing together.
struct ReplicatorSpec {
    var cell: VisualizerCell = .quad
    var layout: ReplicatorLayout = .burst
    var count: Int = 96
    var spin: Float = 0.1
    var size: Float = 0.035
    var sequence: Float = 1.2
    var sequenceOffset: Float = 2.2
    var radius: Float = 0.85
}

/// Motion's simulation behaviors as a force field applied to every particle.
/// Attaching forces to the emitter rather than to each particle is what lets a
/// few numbers produce completely different swarms.
struct ForceField {
    var vortex: Float = 0
    var orbit: Float = 0
    var attractor: Float = 0
    var repel: Float = 0
    var gravity: Float = 0
    var wind: SIMD2<Float> = .zero
    var drag: Float = 0.02
    var randomMotion: Float = 0
    var emitLayout: ReplicatorLayout = .ring
    var emitRadius: Float = 0.4
    var rate: Float = 10
    var lifetime: Float = 0.006
}

/// A preset is a mode plus the feedback transform applied to the previous
/// frame. The same geometry looks completely different tunnelled, spiralled or
/// smeared, which is how G-Force and MilkDrop got so much variety out of a
/// handful of primitives.
struct VisualizerPreset {
    var name: String
    var mode: VisualizerMode
    var zoom: Float = 1
    var rot: Float = 0
    var warp: Float = 0
    var dx: Float = 0
    var dy: Float = 0
    var decay: Float = 0.90
    var paletteShift: Float = 0
    var overlayAlpha: Float = 1
    /// Which colour ramp CPU-built geometry uses; see `VisualizerRenderer.ramps`.
    var palette: Int = 0
    /// Shader modes only: add onto the trails instead of blending over them.
    var additive: Bool = false
    var bloom: Float = 0.6
    /// Per-preset constant some shaders use to pick a different region.
    var seed: Float = 0

    /// Sensible feedback for a mode chosen by hand from the menu.
    static func standard(for mode: VisualizerMode) -> VisualizerPreset {
        switch mode {
        case .bars, .mirror:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.004, decay: 0.55)
        case .radial:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.012, rot: 0.004, decay: 0.86)
        case .tunnel:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.02, decay: 0.88)
        case .scope, .ribbon:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.006, warp: 0.5, decay: 0.93)
        case .lissajous:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.008, rot: 0.006, warp: 0.7, decay: 0.95)
        case .bloom, .starfield:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.01, decay: 0.92)
        case .matrix:
            return VisualizerPreset(name: mode.rawValue, mode: mode, decay: 0.84)
        case .milkdrop:
            // Decay and the whole transform come from the preset's own
            // equations; only the waveform drawn on top is ours.
            return VisualizerPreset(name: mode.rawValue, mode: .scope, decay: 0.96)
        case .rays, .laser, .eclipse, .strings:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.014, decay: 0.84,
                                    overlayAlpha: 0.45, additive: true)
        case .sonar, .circuit, .galaxy:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.006, decay: 0.72,
                                    overlayAlpha: 0.7, additive: true)
        default:
            if mode.replicatorSpec != nil {
                return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.008, rot: 0.003,
                                        warp: 0.4, decay: 0.90)
            }
            if mode.forceSpec != nil {
                return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.012, rot: 0.004,
                                        decay: 0.93)
            }
            return VisualizerPreset(name: mode.rawValue, mode: mode, decay: 0)
        }
    }

    /// The hand-tuned presets the shuffle draws from. Deliberately varied:
    /// tunnels, spirals, drifts, scenes and layered shader beds.
    static let rotation: [VisualizerPreset] = [
        VisualizerPreset(name: "Vortex", mode: .radial, zoom: 1.03, rot: 0.013, warp: 0.6, decay: 0.94),
        VisualizerPreset(name: "Deep Tunnel", mode: .tunnel, zoom: 1.045, rot: -0.006, decay: 0.86, paletteShift: 0.3, palette: 1),
        VisualizerPreset(name: "Silk", mode: .lissajous, zoom: 1.006, rot: 0.011, warp: 1.4, decay: 0.96, paletteShift: 0.6, palette: 4),
        VisualizerPreset(name: "Ion Storm", mode: .bloom, zoom: 1.028, rot: -0.014, warp: 0.9, decay: 0.95, palette: 3),
        VisualizerPreset(name: "Rainfall", mode: .matrix, zoom: 0.995, dy: 0.6, decay: 0.90, paletteShift: 0.45),
        VisualizerPreset(name: "Hyperspace", mode: .starfield, zoom: 1.05, rot: 0.004, decay: 0.94, paletteShift: 0.15, palette: 3),
        VisualizerPreset(name: "Liquid Bars", mode: .mirror, zoom: 1.016, warp: 1.6, decay: 0.92, paletteShift: 0.7, palette: 1),
        VisualizerPreset(name: "Aurora Drift", mode: .aurora, decay: 0.88, paletteShift: 0.2, overlayAlpha: 0.45),
        VisualizerPreset(name: "Nebula Bloom", mode: .nebula, zoom: 1.02, rot: 0.005, decay: 0.90, overlayAlpha: 0.35),
        VisualizerPreset(name: "Kaleido Spin", mode: .kaleidoscope, zoom: 1.01, rot: -0.018, decay: 0.85, overlayAlpha: 0.5),
        VisualizerPreset(name: "Plasma Wash", mode: .plasma, zoom: 1.008, warp: 1.1, decay: 0.86, paletteShift: 0.55, overlayAlpha: 0.4),
        VisualizerPreset(name: "Warp Core", mode: .warp, zoom: 1.015, rot: 0.007, decay: 0.87, overlayAlpha: 0.5),
        VisualizerPreset(name: "Metaflow", mode: .metaballs, zoom: 1.012, rot: -0.004, warp: 0.8, decay: 0.88, overlayAlpha: 0.45),
        VisualizerPreset(name: "Ribbon Trails", mode: .ribbon, zoom: 1.01, rot: 0.009, warp: 1.2, decay: 0.95, paletteShift: 0.35, palette: 5),
        VisualizerPreset(name: "Slow Burn", mode: .scope, zoom: 1.002, rot: -0.003, warp: 1.8, decay: 0.97, paletteShift: 0.8, palette: 2),
        // Replicators and simulations
        VisualizerPreset(name: "Sunburst", mode: .burst, zoom: 1.018, rot: 0.006, warp: 0.5, decay: 0.93, paletteShift: 0.25, palette: 2),
        VisualizerPreset(name: "Double Helix", mode: .helix, zoom: 1.01, rot: -0.012, warp: 0.7, decay: 0.94, paletteShift: 0.5, palette: 1),
        VisualizerPreset(name: "Signal Wave", mode: .waveform, zoom: 1.006, warp: 1.0, dx: 0.4, decay: 0.94, paletteShift: 0.65),
        VisualizerPreset(name: "Lattice", mode: .grid, zoom: 1.022, rot: 0.008, decay: 0.90, paletteShift: 0.15, palette: 3),
        VisualizerPreset(name: "Confetti", mode: .scatter, zoom: 1.014, rot: -0.007, warp: 1.3, decay: 0.92, paletteShift: 0.85, palette: 6),
        VisualizerPreset(name: "Orbit Cloud", mode: .orbitals, zoom: 1.02, rot: 0.005, warp: 0.6, decay: 0.95, palette: 5),
        VisualizerPreset(name: "Swarm", mode: .swarm, zoom: 1.016, rot: -0.009, warp: 0.9, decay: 0.95, paletteShift: 0.4, palette: 4),
        VisualizerPreset(name: "Downpour", mode: .cascade, zoom: 0.997, dy: 0.5, decay: 0.93, paletteShift: 0.7, palette: 3),
        VisualizerPreset(name: "Crown", mode: .halo, zoom: 1.03, rot: 0.01, warp: 0.4, decay: 0.94, palette: 4),
        VisualizerPreset(name: "Pinwheel", mode: .pinwheel, zoom: 1.012, rot: 0.016, warp: 0.5, decay: 0.93, palette: 6),
        VisualizerPreset(name: "Stained Glass", mode: .mosaic, zoom: 1.02, rot: -0.005, warp: 1.1, decay: 0.92, palette: 1),
        VisualizerPreset(name: "Maelstrom", mode: .maelstrom, zoom: 0.992, rot: 0.012, decay: 0.95, palette: 3),
        VisualizerPreset(name: "Fireflies", mode: .fireflies, zoom: 1.004, warp: 0.6, decay: 0.96, palette: 2),
        VisualizerPreset(name: "Fountain", mode: .fountain, zoom: 1.01, dy: 0.25, decay: 0.94, palette: 1),
        // Scenes
        VisualizerPreset(name: "Outrun", mode: .outrun, decay: 0, bloom: 0.8),
        VisualizerPreset(name: "Ridgeline", mode: .ridgeline, decay: 0, paletteShift: 0.55, bloom: 0.9),
        VisualizerPreset(name: "Skyline", mode: .skyline, decay: 0, paletteShift: 0.05, bloom: 0.7),
        VisualizerPreset(name: "Neon City", mode: .skyline, decay: 0, paletteShift: 0.55, bloom: 0.9),
        VisualizerPreset(name: "Glacier", mode: .ridgeline, decay: 0, paletteShift: 0.05, bloom: 0.9),
        // Shader beds
        VisualizerPreset(name: "Julia Dream", mode: .fractal, zoom: 1.006, rot: 0.002, decay: 0.80, paletteShift: 0.1, overlayAlpha: 0.55),
        VisualizerPreset(name: "Fractal Dive", mode: .fractal, zoom: 1.04, rot: -0.01, decay: 0.92, paletteShift: 0.6, overlayAlpha: 0.3, seed: 0.5),
        VisualizerPreset(name: "Cell Division", mode: .cells, zoom: 1.01, decay: 0.82, paletteShift: 0.35, overlayAlpha: 0.5),
        VisualizerPreset(name: "Time Tunnel", mode: .chrono, zoom: 1.012, rot: 0.004, decay: 0.80, paletteShift: 0.6, overlayAlpha: 0.6),
        VisualizerPreset(name: "Pulsar", mode: .orb, zoom: 1.035, rot: 0.003, decay: 0.90, paletteShift: 0.55, overlayAlpha: 0.7),
        VisualizerPreset(name: "Molten Core", mode: .orb, zoom: 1.02, rot: -0.008, warp: 0.6, decay: 0.92, paletteShift: 0.0, overlayAlpha: 0.6),
        VisualizerPreset(name: "God Rays", mode: .rays, zoom: 1.02, rot: 0.003, decay: 0.88, paletteShift: 0.05, overlayAlpha: 0.5, additive: true),
        VisualizerPreset(name: "Hive Mind", mode: .hive, zoom: 1.006, decay: 0.70, paletteShift: 0.1, overlayAlpha: 0.6),
        VisualizerPreset(name: "Ink in Water", mode: .ink, zoom: 1.004, warp: 0.6, decay: 0.85, paletteShift: 0.6, overlayAlpha: 0.4),
        VisualizerPreset(name: "Laser Show", mode: .laser, zoom: 1.03, rot: 0.01, decay: 0.90, paletteShift: 0.5, overlayAlpha: 0.32, additive: true),
        VisualizerPreset(name: "Laser Tunnel", mode: .laser, zoom: 1.07, rot: -0.02, decay: 0.90, paletteShift: 0.9, overlayAlpha: 0.30, additive: true),
        VisualizerPreset(name: "Spiral Galaxy", mode: .galaxy, zoom: 1.004, rot: 0.003, decay: 0.80, paletteShift: 0.55, overlayAlpha: 0.7, additive: true),
        VisualizerPreset(name: "Sonar", mode: .sonar, zoom: 1.015, decay: 0.85, paletteShift: 0.3, overlayAlpha: 0.55, additive: true),
        VisualizerPreset(name: "Circuit Board", mode: .circuit, zoom: 1.01, decay: 0.80, paletteShift: 0.3, overlayAlpha: 0.6, additive: true),
        VisualizerPreset(name: "Eclipse", mode: .eclipse, zoom: 1.012, rot: -0.004, decay: 0.90, overlayAlpha: 0.5, additive: true),
        VisualizerPreset(name: "Solar Flare", mode: .eclipse, zoom: 1.03, rot: 0.008, warp: 0.8, decay: 0.88, paletteShift: 0.45, overlayAlpha: 0.28, additive: true),
        VisualizerPreset(name: "Harp", mode: .strings, warp: 0.8, decay: 0.88, paletteShift: 0.2, overlayAlpha: 0.45, additive: true),
        VisualizerPreset(name: "Tightrope", mode: .strings, zoom: 1.03, rot: 0.006, decay: 0.90, paletteShift: 0.7, overlayAlpha: 0.35, additive: true)
    ]

    /// A freshly invented preset: a random mode under a random feedback
    /// transform and palette. This is what keeps the shuffle from ever
    /// running out — the hand-tuned list is finite, this is not.
    static func remix(avoiding avoided: VisualizerMode? = nil) -> VisualizerPreset {
        var pool = VisualizerMode.selectable
        if let avoided, pool.count > 1 { pool.removeAll { $0 == avoided } }
        let mode = pool.randomElement() ?? .bars

        var preset = VisualizerPreset(name: mode.rawValue, mode: mode)
        preset.paletteShift = Float.random(in: 0...1)
        preset.palette = Int.random(in: 0..<VisualizerRenderer.rampCount)
        preset.seed = Float.random(in: 0...1)
        preset.bloom = Float.random(in: 0.45...0.95)

        if mode.isScene {
            // A scene fills the frame; only its colours vary.
            preset.decay = 0
            preset.name = Self.sceneNames.randomElement().map { "\($0) \(mode.rawValue)" } ?? mode.rawValue
            return preset
        }

        // One of a few distinct kinds of motion, so remixes differ in
        // character rather than only in degree.
        let style = Int.random(in: 0..<5)
        let sign: Float = Bool.random() ? 1 : -1
        let adjective: String
        switch style {
        case 0:
            adjective = "Tunnelled"
            preset.zoom = Float.random(in: 1.03...1.07)
            preset.rot = sign * Float.random(in: 0...0.008)
            preset.decay = Float.random(in: 0.92...0.95)
        case 1:
            adjective = "Spiral"
            preset.zoom = Float.random(in: 1.008...1.03)
            preset.rot = sign * Float.random(in: 0.012...0.03)
            preset.decay = Float.random(in: 0.92...0.96)
        case 2:
            adjective = "Liquid"
            preset.zoom = Float.random(in: 1.0...1.012)
            preset.warp = Float.random(in: 1.2...2.4)
            preset.decay = Float.random(in: 0.93...0.965)
        case 3:
            adjective = "Drifting"
            preset.zoom = Float.random(in: 0.994...1.008)
            preset.dx = Float.random(in: -0.6...0.6)
            preset.dy = Float.random(in: -0.6...0.6)
            preset.warp = Float.random(in: 0...0.8)
            preset.decay = Float.random(in: 0.90...0.95)
        default:
            adjective = "Imploding"
            preset.zoom = Float.random(in: 0.965...0.99)
            preset.rot = sign * Float.random(in: 0.004...0.016)
            preset.decay = Float.random(in: 0.92...0.95)
        }

        if mode.isProcedural {
            preset.additive = mode.prefersAdditive
            // Added light piles up in the trails far faster than blended light.
            preset.overlayAlpha = mode.prefersAdditive ? Float.random(in: 0.25...0.40) : Float.random(in: 0.35...0.65)
            // A bed redrawn every frame needs less persistence to stay legible.
            preset.decay = min(preset.decay, Float.random(in: 0.84...0.93))
        }
        preset.name = "\(adjective) \(mode.rawValue)"
        return preset
    }

    private static let sceneNames = ["Midnight", "Electric", "Crimson", "Arctic", "Golden", "Violet"]
}

struct VisualizerModeGroup: Identifiable {
    let id: String
    let modes: [VisualizerMode]
}

// MARK: - Vertex

/// Laid out to match `VIn` in the shader: float2 at 0, float4 at 16 (its own
/// alignment), float at 32, 48-byte stride.
private struct VisualizerVertex {
    var pos: SIMD2<Float>
    var color: SIMD4<Float>
    var size: Float
}

/// Matches `WarpIn`: two float2s, 16-byte stride.
private struct WarpVertex {
    var pos: SIMD2<Float>
    var uv: SIMD2<Float>
}

/// Matches `Uniforms` in the shader: twenty floats then an int, 84-byte stride.
private struct VisualizerUniforms {
    var time: Float
    var bass: Float
    var level: Float
    var aspect: Float
    var decay: Float
    var zoom: Float
    var rot: Float
    var warp: Float
    var dx: Float
    var dy: Float
    var paletteShift: Float
    var overlayAlpha: Float
    var mid: Float
    var treb: Float
    var beat: Float
    var fade: Float
    var seed: Float
    var histHead: Float
    var bloom: Float
    var pad: Float = 0
    var mode: Int32
}

// MARK: - Particle

private struct Particle {
    var pos: SIMD2<Float>
    var velocity: SIMD2<Float>
    var life: Float
    var hue: Float
}

// MARK: - Renderer

/// Builds vertices on the CPU and hands them to a trivial pass-through
/// pipeline. The audio path runs on a realtime thread, so keeping the drawing
/// on the GPU rather than in a SwiftUI `Canvas` avoids competing with it for
/// CPU at 60 fps.
final class VisualizerRenderer: NSObject, MTKViewDelegate {
    var mode: VisualizerMode = .bars {
        didSet {
            guard oldValue != mode else { return }
            beginTransition()
            if mode == .auto && history.isEmpty { nextPreset() }
        }
    }
    /// Set by the view; called on the main thread each frame.
    var frameProvider: (() -> VisualizerFrame)?
    /// Reports the shuffle's current preset so the chrome can name it.
    var onPresetChange: ((String) -> Void)?

    /// Seconds of audio a shuffled preset is held before the next beat cuts it.
    var dwell: Float = 30
    /// Holds the shuffle on the current preset.
    var isLocked = false
    /// Renders exactly this preset whatever the mode; used to render a
    /// preset on its own, outside the shuffle.
    var presetOverride: VisualizerPreset?
    /// Imported MilkDrop presets the shuffle may also land on.
    var milkdropPool: [MilkdropPreset] = []

    private let commandQueue: MTLCommandQueue
    private let solidPipeline: MTLRenderPipelineState
    private let pointPipeline: MTLRenderPipelineState
    private let feedbackPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let proceduralPipeline: MTLRenderPipelineState
    private let proceduralAddPipeline: MTLRenderPipelineState
    private let warpMeshPipeline: MTLRenderPipelineState

    private var vertices: [VisualizerVertex] = []
    private var vertexBuffer: MTLBuffer?
    private var vertexCapacity = 0

    private var particles: [Particle] = []
    private var stars: [Particle] = []
    private var drops: [Particle] = []
    private var simParticles: [Particle] = []

    /// The imported MilkDrop preset driving the warp, if any.
    var milkdrop: MilkdropPreset?
    private var warpVertices: [WarpVertex] = []
    private var warpBuffer: MTLBuffer?
    private var warpCapacity = 0
    private var bandAverages = SIMD3<Double>(0.02, 0.02, 0.02)
    private var elapsed: Double = 0
    private var smoothedSpectrum = [Float](repeating: 0, count: 64)
    private var bassEnvelope: Float = 0
    /// Smoothed overall energy; scales the master clock.
    private var audioMotion: Float = 0
    private var lastBass: Float = 0
    private var phase: Float = 0
    private var midEnergy: Float = 0
    private var trebleEnergy: Float = 0
    /// Jumps to one on a beat and falls away; shaders use it as an accent.
    private var beatPulse: Float = 0

    private let device: MTLDevice
    private let uniformBuffer: MTLBuffer
    private let spectrumBuffer: MTLBuffer
    private let waveformBuffer: MTLBuffer

    /// The accumulation format. Floating point so slow decays fade all the way
    /// to black (8-bit trails stall a few levels above it) and so additive
    /// layers keep the headroom the bloom is drawn from.
    private static let accumFormat: MTLPixelFormat = .rgba16Float

    /// Geometry accumulates here instead of straight into the drawable: the
    /// swap chain rotates through several drawables, so "last frame" only
    /// exists if we keep it ourselves. This is what makes trails possible.
    private var accumTextures: [MTLTexture] = []
    private var accumIndex = 0
    private var accumNeedsClear = true

    /// A ring of past spectra, one row each, for the modes that draw time:
    /// the ridgelines, the skyline and the polar spectrogram. Rows are pushed
    /// by the audio clock, so the history stops with the music.
    private static let historyRows = 128
    private let historyTexture: MTLTexture?
    private var historyHead = 0
    private var historyAccum: Float = 0
    private var historyRow = [UInt8](repeating: 0, count: 64)

    /// Shuffle state. `history` is what Previous walks back through.
    private struct AutoPick {
        var preset: VisualizerPreset
        var milkdrop: MilkdropPreset?
    }
    private var history: [AutoPick] = []
    private var historyIndex = -1
    private var bag: [Int] = []
    private var presetElapsed: Float = 0
    private var beatHold: Float = 0
    /// 0 → 1 over a transition; scales the new content's alpha so a preset
    /// fades in over the old one's trails instead of cutting.
    private var fade: Float = 1
    private var pointScale: Float = 1
    /// The colour ramp of the preset being drawn; see `ramps`.
    private var activePalette = 0

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: visualizerShaderSource, options: nil)
        } catch {
            NSLog("Visualizer shaders failed to compile: %@", String(describing: error))
            return nil
        }

        guard let queue = device.makeCommandQueue(),
              let vfn = library.makeFunction(name: "v_main"),
              let vfull = library.makeFunction(name: "v_full"),
              let solidFn = library.makeFunction(name: "f_solid"),
              let pointFn = library.makeFunction(name: "f_point"),
              let feedbackFn = library.makeFunction(name: "f_feedback"),
              let compFn = library.makeFunction(name: "f_composite"),
              let procFn = library.makeFunction(name: "f_procedural"),
              let warpVFn = library.makeFunction(name: "v_warpmesh"),
              let warpFFn = library.makeFunction(name: "f_warpmesh"),
              let uniforms = device.makeBuffer(length: MemoryLayout<VisualizerUniforms>.stride,
                                               options: .storageModeShared),
              let spectrum = device.makeBuffer(length: 64 * MemoryLayout<Float>.stride,
                                               options: .storageModeShared),
              let waveform = device.makeBuffer(length: 256 * MemoryLayout<Float>.stride,
                                               options: .storageModeShared)
        else { return nil }

        self.device = device
        commandQueue = queue
        uniformBuffer = uniforms
        spectrumBuffer = spectrum
        waveformBuffer = waveform
        memset(waveform.contents(), 0, waveform.length)

        let historyDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: 64, height: Self.historyRows, mipmapped: false
        )
        historyDesc.usage = [.shaderRead]
        historyTexture = device.makeTexture(descriptor: historyDesc)
        if let historyTexture {
            let zeros = [UInt8](repeating: 0, count: 64 * Self.historyRows)
            historyTexture.replace(region: MTLRegionMake2D(0, 0, 64, Self.historyRows),
                                   mipmapLevel: 0, withBytes: zeros, bytesPerRow: 64)
        }

        func pipeline(_ vertex: MTLFunction, _ fragment: MTLFunction, blend: BlendMode,
                      format: MTLPixelFormat = VisualizerRenderer.accumFormat) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertex
            desc.fragmentFunction = fragment
            guard let attachment = desc.colorAttachments[0] else { return nil }
            attachment.pixelFormat = format
            switch blend {
            case .none:
                attachment.isBlendingEnabled = false
            case .alpha, .additive:
                attachment.isBlendingEnabled = true
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.sourceAlphaBlendFactor = .sourceAlpha
                let dst: MTLBlendFactor = blend == .additive ? .one : .oneMinusSourceAlpha
                attachment.destinationRGBBlendFactor = dst
                attachment.destinationAlphaBlendFactor = dst
            }
            do {
                return try device.makeRenderPipelineState(descriptor: desc)
            } catch {
                NSLog("Visualizer pipeline failed: %@", String(describing: error))
                return nil
            }
        }

        guard let solid = pipeline(vfn, solidFn, blend: .alpha),
              let point = pipeline(vfn, pointFn, blend: .additive),
              let feedback = pipeline(vfull, feedbackFn, blend: .none),
              let comp = pipeline(vfull, compFn, blend: .none, format: pixelFormat),
              let proc = pipeline(vfull, procFn, blend: .alpha),
              let procAdd = pipeline(vfull, procFn, blend: .additive),
              let warpMesh = pipeline(warpVFn, warpFFn, blend: .none) else { return nil }

        solidPipeline = solid
        pointPipeline = point
        feedbackPipeline = feedback
        compositePipeline = comp
        proceduralPipeline = proc
        proceduralAddPipeline = procAdd
        warpMeshPipeline = warpMesh
        super.init()
    }

    private enum BlendMode { case none, alpha, additive }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        accumTextures = []
    }

    // MARK: Shuffle

    /// The preset actually being rendered: the shuffle's pick when Auto is
    /// selected, otherwise the standard feedback for the chosen mode.
    private var activePreset: VisualizerPreset {
        if let presetOverride { return presetOverride }
        if mode == .auto, history.indices.contains(historyIndex) {
            return history[historyIndex].preset
        }
        return VisualizerPreset.standard(for: mode == .auto ? .bars : mode)
    }

    /// The MilkDrop preset warping this frame, whether chosen by hand or
    /// landed on by the shuffle.
    private var activeMilkdrop: MilkdropPreset? {
        if mode == .milkdrop { return milkdrop }
        if mode == .auto, history.indices.contains(historyIndex) {
            return history[historyIndex].milkdrop
        }
        return nil
    }

    var activePresetName: String { activePreset.name }

    /// Steps forward: back up the history if Previous was used, otherwise a
    /// new random pick.
    func nextPreset() {
        guard mode == .auto else { return }
        if historyIndex < history.count - 1 {
            historyIndex += 1
        } else {
            history.append(randomPick())
            if history.count > 64 { history.removeFirst(history.count - 64) }
            historyIndex = history.count - 1
        }
        presetChanged()
    }

    func previousPreset() {
        guard mode == .auto, historyIndex > 0 else { return }
        historyIndex -= 1
        presetChanged()
    }

    private func presetChanged() {
        presetElapsed = 0
        beatHold = 0.4
        beginTransition()
        let name = activePreset.name
        onPresetChange?(name)
    }

    /// Nothing is cleared: the old picture stays in the feedback buffer and is
    /// carried off by the new preset's transform while the new content fades
    /// in. Only the particle systems are emptied, since they belong to a mode.
    private func beginTransition() {
        fade = 0
        particles.removeAll(keepingCapacity: true)
        stars.removeAll(keepingCapacity: true)
        drops.removeAll(keepingCapacity: true)
        simParticles.removeAll(keepingCapacity: true)
    }

    /// A shuffled bag of the hand-tuned presets, so none repeats until all
    /// have played, interleaved with freshly remixed ones and — when the user
    /// has imported any — MilkDrop presets.
    private func randomPick() -> AutoPick {
        let current = history.last?.preset.mode

        if !milkdropPool.isEmpty, history.last?.milkdrop == nil, Float.random(in: 0...1) < 0.15,
           let imported = milkdropPool.randomElement() {
            var preset = VisualizerPreset.standard(for: .milkdrop)
            preset.name = imported.name
            return AutoPick(preset: preset, milkdrop: imported)
        }

        if Float.random(in: 0...1) < 0.35 {
            return AutoPick(preset: VisualizerPreset.remix(avoiding: current), milkdrop: nil)
        }

        if bag.isEmpty { bag = Array(VisualizerPreset.rotation.indices).shuffled() }
        // Avoid the same mode twice running where the bag allows it.
        if let current, bag.count > 1, VisualizerPreset.rotation[bag[bag.count - 1]].mode == current {
            bag.swapAt(bag.count - 1, Int.random(in: 0..<(bag.count - 1)))
        }
        return AutoPick(preset: VisualizerPreset.rotation[bag.removeLast()], milkdrop: nil)
    }

    /// Hold each preset for the dwell, then switch on the next beat so the
    /// change lands with the music rather than at an arbitrary moment. The
    /// dwell counts audio time only: silence neither advances nor switches.
    private func advanceAutoCycle(rising: Float) {
        guard mode == .auto else {
            presetElapsed = 0
            return
        }
        if history.isEmpty { nextPreset() }
        guard !isLocked else { return }

        if audioMotion > 0.01 { presetElapsed += 1.0 / 60.0 }
        beatHold = max(0, beatHold - 1.0 / 60.0)

        let beat = rising > 0.06 && beatHold <= 0
        if presetElapsed > dwell * 1.6 || (presetElapsed > dwell && beat) {
            nextPreset()
        }
    }

    // MARK: Targets

    /// Two textures: the warp pass reads one and writes the other, so a frame
    /// can never sample the target it is drawing into. Both carry a mip chain,
    /// regenerated each frame, which the composite pass reads as bloom.
    private func ensureAccum(size: CGSize) -> Bool {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        if accumTextures.count == 2,
           accumTextures[0].width == width, accumTextures[0].height == height {
            return true
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.accumFormat, width: width, height: height, mipmapped: true
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let a = device.makeTexture(descriptor: desc),
              let b = device.makeTexture(descriptor: desc) else { return false }
        accumTextures = [a, b]
        accumNeedsClear = true
        return true
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let present = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let frame = frameProvider?() ?? VisualizerFrame(
            waveform: [Float](repeating: 0, count: 256),
            spectrum: [Float](repeating: 0, count: 64),
            bass: 0, level: 0
        )
        guard encode(frame: frame, size: view.drawableSize, present: present,
                     commandBuffer: commandBuffer) else { return }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// One whole frame — feedback, content, bloom, tone map — encoded into
    /// `commandBuffer`, ending in `present`. Split from `draw(in:)` so a frame
    /// can be rendered into any texture, not only a view's drawable.
    func encode(frame: VisualizerFrame, size: CGSize, present: MTLRenderPassDescriptor,
                commandBuffer: MTLCommandBuffer) -> Bool {
        guard ensureAccum(size: size) else { return false }

        let aspect = Float(size.width / max(1, size.height))
        // Point sprites are sized in pixels; keep them the same share of the
        // picture whatever the window or display scale.
        pointScale = max(0.3, Float(size.height) / 1100)
        advance(frame: frame)

        let preset = activePreset
        let effectiveMode = preset.mode
        let warpPreset = activeMilkdrop
        uploadUniforms(aspect: aspect, frame: frame, preset: preset)

        let source = accumTextures[accumIndex]
        let target = accumTextures[1 - accumIndex]

        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = target
        scenePass.colorAttachments[0].loadAction = accumNeedsClear ? .clear : .dontCare
        scenePass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        scenePass.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePass) {
            // 1 — warp and dim the previous frame into the target.
            if let warpPreset {
                buildWarpMesh(preset: warpPreset, frame: frame)
                if !accumNeedsClear, let mesh = warpBuffer, !warpVertices.isEmpty {
                    encoder.setRenderPipelineState(warpMeshPipeline)
                    encoder.setVertexBuffer(mesh, offset: 0, index: 0)
                    encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                    encoder.setFragmentTexture(source, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: warpVertices.count)
                }
            } else if !accumNeedsClear {
                encoder.setRenderPipelineState(feedbackPipeline)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(source, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            accumNeedsClear = false

            // 2 — draw this frame's content over it.
            if effectiveMode.isProcedural {
                encoder.setRenderPipelineState(preset.additive ? proceduralAddPipeline : proceduralPipeline)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(spectrumBuffer, offset: 0, index: 1)
                encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
                encoder.setFragmentTexture(historyTexture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            } else {
                buildVertices(mode: effectiveMode, frame: frame, aspect: aspect)
                if !vertices.isEmpty, let buffer = ensureBuffer(count: vertices.count) {
                    buffer.contents().copyMemory(
                        from: vertices,
                        byteCount: vertices.count * MemoryLayout<VisualizerVertex>.stride
                    )
                    encoder.setRenderPipelineState(effectiveMode.isParticle ? pointPipeline : solidPipeline)
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                    encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                    encoder.drawPrimitives(
                        type: effectiveMode.isParticle ? .point : .triangle,
                        vertexStart: 0,
                        vertexCount: vertices.count
                    )
                }
            }
            encoder.endEncoding()
        }

        // 3 — rebuild the mip chain the bloom reads.
        if target.mipmapLevelCount > 1, let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: target)
            blit.endEncoding()
        }

        // 4 — bloom and tone-map onto the destination.
        present.colorAttachments[0].loadAction = .dontCare
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: present) {
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(target, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        accumIndex = 1 - accumIndex
        return true
    }

    private func uploadUniforms(aspect: Float, frame: VisualizerFrame, preset: VisualizerPreset) {
        // While a preset fades in, the outgoing picture is held a little
        // longer than the new decay alone would allow, so it dissolves into
        // the new one rather than vanishing under it.
        let decay = fade < 1 ? max(preset.decay, 0.97 + (preset.decay - 0.97) * fade) : preset.decay

        var uniforms = VisualizerUniforms(
            time: phase * 4,
            bass: bassEnvelope,
            level: frame.level,
            aspect: aspect,
            decay: decay,
            zoom: preset.zoom,
            rot: preset.rot,
            warp: preset.warp,
            dx: preset.dx,
            dy: preset.dy,
            paletteShift: preset.paletteShift,
            overlayAlpha: preset.overlayAlpha,
            mid: midEnergy,
            treb: trebleEnergy,
            beat: beatPulse,
            fade: fade,
            seed: preset.seed,
            histHead: (Float(historyHead) + 0.5) / Float(Self.historyRows),
            bloom: preset.bloom,
            mode: preset.mode.proceduralIndex ?? 0
        )
        uniformBuffer.contents().copyMemory(
            from: &uniforms, byteCount: MemoryLayout<VisualizerUniforms>.stride
        )
        smoothedSpectrum.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            spectrumBuffer.contents().copyMemory(
                from: base, byteCount: min(64, src.count) * MemoryLayout<Float>.stride
            )
        }
        frame.waveform.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            waveformBuffer.contents().copyMemory(
                from: base, byteCount: min(256, src.count) * MemoryLayout<Float>.stride
            )
        }
    }

    /// Appends the current spectrum to the history ring.
    private func pushHistoryRow() {
        guard let historyTexture else { return }
        historyHead = (historyHead + 1) % Self.historyRows
        for i in 0..<64 {
            historyRow[i] = UInt8(max(0, min(255, smoothedSpectrum[i] * 255)))
        }
        historyTexture.replace(region: MTLRegionMake2D(0, historyHead, 64, 1),
                               mipmapLevel: 0, withBytes: historyRow, bytesPerRow: 64)
    }

    // MARK: Frame state

    private func advance(frame: VisualizerFrame) {
        // The clock is driven by the audio, not by wall time. Every time-based
        // motion in every mode reads `phase`, so with no sound nothing moves
        // anywhere: shader patterns, replicator spin, the sequence wave and the
        // feedback ripple all stop together. A visual that animates in silence
        // is decoration, not a visualiser.
        let energy = max(frame.level, bassEnvelope)
        audioMotion += (energy - audioMotion) * (energy > audioMotion ? 0.45 : 0.06)
        let step = 0.012 * min(3.0, audioMotion * 3.4)
        phase += step

        // The history ring is pushed by the same clock, at most a row a frame.
        historyAccum += step
        if historyAccum >= 0.009 {
            historyAccum = 0
            pushHistoryRow()
        }

        // Attack fast, release slow: a kick should snap and then fall away.
        for i in smoothedSpectrum.indices where i < frame.spectrum.count {
            let target = frame.spectrum[i]
            let rate: Float = target > smoothedSpectrum[i] ? 0.55 : 0.12
            smoothedSpectrum[i] += (target - smoothedSpectrum[i]) * rate
        }

        bassEnvelope += (frame.bass - bassEnvelope) * (frame.bass > bassEnvelope ? 0.6 : 0.08)
        let rising = max(0, frame.bass - lastBass)
        lastBass = frame.bass

        var mid: Float = 0
        var treble: Float = 0
        for i in 16..<41 { mid += smoothedSpectrum[i] }
        for i in 41..<64 { treble += smoothedSpectrum[i] }
        midEnergy = mid / 25
        trebleEnergy = treble / 23

        if rising > 0.06 { beatPulse = 1 }
        beatPulse *= 0.90
        if beatPulse < 0.002 { beatPulse = 0 }

        // Wall-clock, unlike everything else: a transition has to finish even
        // when the mode is changed in silence. It runs once and stops.
        fade = min(1, fade + 1.0 / 75.0)

        advanceAutoCycle(rising: rising)
        let active = activePreset.mode
        activePalette = activePreset.palette

        // Only the active particle system keeps state.
        if active != .bloom { particles.removeAll(keepingCapacity: true) }
        if active != .starfield { stars.removeAll(keepingCapacity: true) }
        if active != .matrix { drops.removeAll(keepingCapacity: true) }
        if active.forceSpec == nil { simParticles.removeAll(keepingCapacity: true) }

        switch active {
        case .bloom: advanceBloom(rising: rising)
        case .starfield: advanceStars(level: frame.level)
        case .matrix: advanceDrops()
        default:
            if let forces = active.forceSpec {
                advanceSimulation(forces, level: frame.level)
            }
        }
    }

    /// A rising edge in bass is the beat; emit a burst on it.
    private func advanceBloom(rising: Float) {
        let burst = Int(rising * 260)
        if burst > 0 && particles.count < 1400 {
            for _ in 0..<burst {
                let angle = Float.random(in: 0..<(2 * .pi))
                let speed = Float.random(in: 0.12...0.55) * (0.4 + bassEnvelope)
                particles.append(Particle(
                    pos: SIMD2(0, 0),
                    velocity: SIMD2(cos(angle) * speed, sin(angle) * speed),
                    life: 1,
                    hue: Float.random(in: 0...1) * 0.35 + bassEnvelope * 0.4
                ))
            }
        }
        for i in particles.indices {
            particles[i].pos += particles[i].velocity * 0.016
            particles[i].velocity *= 0.985
            particles[i].life -= 0.012
        }
        particles.removeAll { $0.life <= 0 }
    }

    /// Continuous emission from the centre, accelerating outward — flying
    /// through stars, with the throttle on overall level.
    private func advanceStars(level: Float) {
        let spawn = Int(level * 17)
        if stars.count < 1200 {
            for _ in 0..<spawn {
                let angle = Float.random(in: 0..<(2 * .pi))
                let speed = Float.random(in: 0.05...0.14)
                stars.append(Particle(
                    pos: SIMD2(cos(angle) * 0.02, sin(angle) * 0.02),
                    velocity: SIMD2(cos(angle) * speed, sin(angle) * speed),
                    life: 1,
                    hue: Float.random(in: 0.35...1)
                ))
            }
        }
        let boost = 1 + bassEnvelope * 2.2
        for i in stars.indices {
            stars[i].velocity *= 1.035
            stars[i].pos += stars[i].velocity * 0.016 * boost
            stars[i].life -= 0.008
        }
        stars.removeAll { $0.life <= 0 || abs($0.pos.x) > 1.8 || abs($0.pos.y) > 1.8 }
    }

    /// One falling column per spectrum bin; loud bins rain harder.
    private func advanceDrops() {
        let columns = smoothedSpectrum.count
        for c in 0..<columns where smoothedSpectrum[c] > 0.08 {
            if Float.random(in: 0...1) < smoothedSpectrum[c] * 0.5 && drops.count < 1600 {
                let x = -1 + (Float(c) + 0.5) * (2 / Float(columns))
                drops.append(Particle(
                    pos: SIMD2(x, 1.05),
                    velocity: SIMD2(0, -(0.35 + smoothedSpectrum[c] * 1.2)),
                    life: 1,
                    hue: Float(c) / Float(columns - 1)
                ))
            }
        }
        for i in drops.indices {
            drops[i].pos += drops[i].velocity * 0.016
            drops[i].life -= 0.006
        }
        drops.removeAll { $0.life <= 0 || $0.pos.y < -1.1 }
    }

    // MARK: Geometry

    private func buildVertices(mode: VisualizerMode, frame: VisualizerFrame, aspect: Float) {
        vertices.removeAll(keepingCapacity: true)
        guard !mode.isProcedural else { return }
        switch mode {
        case .bars: buildBars()
        case .mirror: buildMirror()
        case .radial: buildRadial(aspect: aspect)
        case .tunnel: buildTunnel(aspect: aspect)
        case .scope: buildScope(waveform: frame.waveform, level: frame.level)
        case .lissajous: buildLissajous(waveform: frame.waveform, aspect: aspect)
        case .ribbon: buildRibbon(waveform: frame.waveform)
        case .bloom: buildPoints(particles, aspect: aspect, base: 6, growth: 26, alpha: 0.85)
        case .starfield: buildStars(aspect: aspect)
        case .matrix: buildPoints(drops, aspect: aspect, base: 3, growth: 9, alpha: 0.9)
        default:
            if let spec = mode.replicatorSpec {
                buildReplicator(spec, aspect: aspect)
            } else if mode.forceSpec != nil {
                buildPoints(simParticles, aspect: aspect, base: 4, growth: 16, alpha: 0.8)
            }
        }
    }

    /// Colour ramps for CPU-built geometry, low frequency to high. Index 0 is
    /// the original green-to-red ramp; a preset picks one with `palette`.
    private static let ramps: [[SIMD3<Float>]] = [
        [],
        // Neon
        [SIMD3(0.10, 0.85, 1.00), SIMD3(0.45, 0.45, 1.00), SIMD3(0.85, 0.30, 1.00), SIMD3(1.00, 0.25, 0.60)],
        // Fire
        [SIMD3(0.75, 0.08, 0.05), SIMD3(1.00, 0.35, 0.05), SIMD3(1.00, 0.75, 0.15), SIMD3(1.00, 0.97, 0.80)],
        // Ice
        [SIMD3(0.15, 0.30, 0.95), SIMD3(0.15, 0.70, 1.00), SIMD3(0.55, 0.95, 1.00), SIMD3(0.95, 1.00, 1.00)],
        // Sunset
        [SIMD3(0.50, 0.20, 0.90), SIMD3(0.95, 0.25, 0.65), SIMD3(1.00, 0.50, 0.25), SIMD3(1.00, 0.85, 0.35)],
        // Aurora
        [SIMD3(0.10, 0.80, 0.75), SIMD3(0.25, 0.95, 0.45), SIMD3(0.45, 0.60, 1.00), SIMD3(0.80, 0.40, 1.00)],
        // Candy
        [SIMD3(1.00, 0.35, 0.55), SIMD3(1.00, 0.80, 0.30), SIMD3(0.35, 0.95, 0.70), SIMD3(0.40, 0.60, 1.00)]
    ]
    static let rampCount = ramps.count

    private func color(at t: Float, alpha: Float = 1) -> SIMD4<Float> {
        let ramp = Self.ramps[min(max(0, activePalette), Self.ramps.count - 1)]
        if !ramp.isEmpty {
            let x = min(max(t, 0), 0.9999) * Float(ramp.count - 1)
            let i = Int(x)
            let c = ramp[i] + (ramp[i + 1] - ramp[i]) * (x - Float(i))
            return SIMD4(c.x, c.y, c.z, alpha)
        }
        // Same low-to-high ramp as the spectrum panel: green -> teal -> yellow -> red.
        if t < 0.4 {
            let k = t / 0.4
            return SIMD4(0.2 + 0.1 * k, 0.85, 0.45 + 0.35 * k, alpha)
        } else if t < 0.7 {
            let k = (t - 0.4) / 0.3
            return SIMD4(0.3 + 0.6 * k, 0.85, 0.8 - 0.6 * k, alpha)
        }
        let k = (t - 0.7) / 0.3
        return SIMD4(0.9 + 0.1 * k, 0.85 - 0.6 * k, 0.2 - 0.15 * k, alpha)
    }

    private func addQuad(x0: Float, y0: Float, x1: Float, y1: Float, color c: SIMD4<Float>) {
        let a = VisualizerVertex(pos: SIMD2(x0, y0), color: c, size: 1)
        let b = VisualizerVertex(pos: SIMD2(x1, y0), color: c, size: 1)
        let d = VisualizerVertex(pos: SIMD2(x0, y1), color: c, size: 1)
        let e = VisualizerVertex(pos: SIMD2(x1, y1), color: c, size: 1)
        vertices.append(contentsOf: [a, b, d, b, e, d])
    }

    private func addLine(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, thickness: Float, color c: SIMD4<Float>) {
        let delta = p1 - p0
        let length = max(1e-6, sqrt(delta.x * delta.x + delta.y * delta.y))
        let normal = SIMD2(-delta.y / length, delta.x / length) * thickness
        let a = VisualizerVertex(pos: p0 - normal, color: c, size: 1)
        let b = VisualizerVertex(pos: p1 - normal, color: c, size: 1)
        let d = VisualizerVertex(pos: p0 + normal, color: c, size: 1)
        let e = VisualizerVertex(pos: p1 + normal, color: c, size: 1)
        vertices.append(contentsOf: [a, b, d, b, e, d])
    }

    /// Classic bottom-up columns.
    private func buildBars() {
        let count = smoothedSpectrum.count
        let slot = 2.0 / Float(count)
        let width = slot * 0.72
        for i in 0..<count {
            let height = max(0.006, smoothedSpectrum[i] * 1.85)
            let x0 = -1 + Float(i) * slot + (slot - width) / 2
            addQuad(x0: x0, y0: -1, x1: x0 + width, y1: -1 + height,
                    color: color(at: Float(i) / Float(count - 1)))
        }
    }

    /// Symmetric about the horizontal centre line.
    private func buildMirror() {
        let count = smoothedSpectrum.count
        let slot = 2.0 / Float(count)
        let width = slot * 0.72
        for i in 0..<count {
            let value = smoothedSpectrum[i]
            let height = max(0.004, value * 0.92)
            let x0 = -1 + Float(i) * slot + (slot - width) / 2
            let t = Float(i) / Float(count - 1)
            addQuad(x0: x0, y0: 0, x1: x0 + width, y1: height, color: color(at: t))
            addQuad(x0: x0, y0: -height, x1: x0 + width, y1: 0, color: color(at: t, alpha: 0.45))
        }
    }

    /// Bars radiating from the centre, rotating slowly.
    private func buildRadial(aspect: Float) {
        let count = smoothedSpectrum.count
        let inner: Float = 0.18 + bassEnvelope * 0.09
        for i in 0..<count {
            for side in 0..<2 {
                let step = Float.pi / Float(count)
                let angle = phase + Float(i) * step + (side == 1 ? .pi : 0)
                let outer = inner + max(0.006, smoothedSpectrum[i] * 0.62)
                let halfWidth = step * 0.36

                func point(_ radius: Float, _ a: Float) -> SIMD2<Float> {
                    SIMD2(cos(a) * radius / max(0.001, aspect), sin(a) * radius)
                }

                let c = color(at: Float(i) / Float(count - 1))
                let p0 = point(inner, angle - halfWidth)
                let p1 = point(inner, angle + halfWidth)
                let p2 = point(outer, angle - halfWidth)
                let p3 = point(outer, angle + halfWidth)
                for p in [p0, p1, p2, p1, p3, p2] {
                    vertices.append(VisualizerVertex(pos: p, color: c, size: 1))
                }
            }
        }
    }

    /// Rings racing outward, each carrying one band's energy — the ring you see
    /// at the rim is what the spectrum looked like a moment ago.
    private func buildTunnel(aspect: Float) {
        let rings = 26
        let segments = 44
        for r in 0..<rings {
            // Squared radius gives the rings a perspective-like acceleration.
            let travel = (phase * 0.22 + Float(r) / Float(rings)).truncatingRemainder(dividingBy: 1)
            let radius = travel * travel * 1.5
            guard radius > 0.02 else { continue }

            let band = min(smoothedSpectrum.count - 1, r * smoothedSpectrum.count / rings)
            let energy = smoothedSpectrum[band]
            let thickness = 0.006 + energy * 0.05
            let fade = (1 - travel) * (0.25 + energy * 0.9)
            let c = color(at: Float(band) / Float(smoothedSpectrum.count - 1), alpha: min(1, fade))

            for sIdx in 0..<segments {
                let a0 = Float(sIdx) / Float(segments) * 2 * .pi + phase * 0.35
                let a1 = Float(sIdx + 1) / Float(segments) * 2 * .pi + phase * 0.35
                func pt(_ rad: Float, _ a: Float) -> SIMD2<Float> {
                    SIMD2(cos(a) * rad / max(0.001, aspect), sin(a) * rad)
                }
                let inner0 = pt(radius - thickness, a0)
                let outer0 = pt(radius + thickness, a0)
                let inner1 = pt(radius - thickness, a1)
                let outer1 = pt(radius + thickness, a1)
                for p in [inner0, outer0, inner1, outer0, outer1, inner1] {
                    vertices.append(VisualizerVertex(pos: p, color: c, size: 1))
                }
            }
        }
    }

    /// Waveform as a thick line.
    private func buildScope(waveform: [Float], level: Float) {
        guard waveform.count > 1 else { return }
        let thickness: Float = 0.006 + level * 0.02
        let step = 2.0 / Float(waveform.count - 1)
        for i in 0..<(waveform.count - 1) {
            let y0 = max(-0.95, min(0.95, waveform[i] * 0.85))
            let y1 = max(-0.95, min(0.95, waveform[i + 1] * 0.85))
            addLine(SIMD2(-1 + Float(i) * step, y0),
                    SIMD2(-1 + Float(i + 1) * step, y1),
                    thickness: thickness,
                    color: color(at: 0.5 + abs(y0) * 0.5))
        }
    }

    /// Vectorscope: the signal plotted against a delayed copy of itself, which
    /// draws the loops an X/Y oscilloscope would show.
    private func buildLissajous(waveform: [Float], aspect: Float) {
        guard waveform.count > 8 else { return }
        let delay = waveform.count / 4
        let thickness: Float = 0.004 + bassEnvelope * 0.012
        for i in 0..<(waveform.count - 1) {
            let x0 = waveform[i] * 0.8 / max(0.001, aspect)
            let y0 = waveform[(i + delay) % waveform.count] * 0.8
            let x1 = waveform[i + 1] * 0.8 / max(0.001, aspect)
            let y1 = waveform[(i + 1 + delay) % waveform.count] * 0.8
            let t = Float(i) / Float(waveform.count - 1)
            addLine(SIMD2(x0, y0), SIMD2(x1, y1), thickness: thickness,
                    color: color(at: t, alpha: 0.9))
        }
    }

    /// The waveform filled to the centre line, so loud passages read as mass
    /// rather than as a thin trace.
    private func buildRibbon(waveform: [Float]) {
        guard waveform.count > 1 else { return }
        let step = 2.0 / Float(waveform.count - 1)
        for i in 0..<(waveform.count - 1) {
            let x0 = -1 + Float(i) * step
            let x1 = x0 + step
            let y0 = max(-0.95, min(0.95, waveform[i] * 0.9))
            let y1 = max(-0.95, min(0.95, waveform[i + 1] * 0.9))
            let t = min(1, (abs(y0) + abs(y1)) * 0.9)
            let c = color(at: t, alpha: 0.28 + t * 0.6)
            // Two triangles spanning from the centre line out to the trace.
            let a = VisualizerVertex(pos: SIMD2(x0, 0), color: color(at: t, alpha: 0.05), size: 1)
            let b = VisualizerVertex(pos: SIMD2(x1, 0), color: color(at: t, alpha: 0.05), size: 1)
            let d = VisualizerVertex(pos: SIMD2(x0, y0), color: c, size: 1)
            let e = VisualizerVertex(pos: SIMD2(x1, y1), color: c, size: 1)
            vertices.append(contentsOf: [a, b, d, b, e, d])
        }
    }

    private func buildPoints(_ set: [Particle], aspect: Float, base: Float, growth: Float, alpha: Float) {
        for p in set {
            let fade = max(0, p.life)
            vertices.append(VisualizerVertex(
                pos: SIMD2(p.pos.x / max(0.001, aspect), p.pos.y),
                color: color(at: p.hue, alpha: fade * alpha),
                size: (base + fade * growth + bassEnvelope * 12) * pointScale
            ))
        }
    }

    /// Stars brighten and swell as they approach the edge.
    private func buildStars(aspect: Float) {
        for star in stars {
            let distance = min(1, sqrt(star.pos.x * star.pos.x + star.pos.y * star.pos.y))
            vertices.append(VisualizerVertex(
                pos: SIMD2(star.pos.x / max(0.001, aspect), star.pos.y),
                color: color(at: star.hue, alpha: min(1, 0.15 + distance * 1.1) * max(0, star.life)),
                size: (1.5 + distance * 7 + bassEnvelope * 10) * pointScale
            ))
        }
    }

    // MARK: Replicators

    private func stableHash(_ i: Int) -> Float {
        let x = sin(Float(i) * 127.1) * 43758.5453
        return x - floor(x)
    }

    private func layoutPosition(_ spec: ReplicatorSpec, index: Int, t: Float,
                                energy: Float, aspect: Float) -> SIMD2<Float> {
        let spin = phase * spec.spin * 8
        switch spec.layout {
        case .burst:
            let angle = t * 2 * .pi + spin
            let r = spec.radius * (0.22 + energy * 0.85)
            return SIMD2(cos(angle) * r / aspect, sin(angle) * r)
        case .spiral:
            let angle = t * 4 * 2 * .pi + spin
            let r = spec.radius * t
            return SIMD2(cos(angle) * r / aspect, sin(angle) * r)
        case .wave:
            let x = -1 + 2 * t
            let y = sin(t * 6 * .pi + spin) * (0.2 + energy * 0.6)
            return SIMD2(x * 0.96, y)
        case .grid:
            let cols = max(1, Int(ceil(sqrt(Float(spec.count)))))
            let row = index / cols
            let col = index % cols
            let x = (Float(col) + 0.5) / Float(cols) * 2 - 1
            let y = (Float(row) + 0.5) / Float(cols) * 2 - 1
            return SIMD2(x * 0.92 / aspect, y * 0.92)
        case .scatter:
            let x = stableHash(index * 2) * 2 - 1
            let y = stableHash(index * 2 + 1) * 2 - 1
            return SIMD2(x * 0.92 / aspect, y * 0.92)
        case .ring:
            let angle = t * 2 * .pi + spin
            return SIMD2(cos(angle) * spec.radius / aspect, sin(angle) * spec.radius)
        }
    }

    /// One cell, as triangles, centred on `at` and rotated by `angle`.
    private func addCell(_ cell: VisualizerCell, at position: SIMD2<Float>, size: Float,
                         angle: Float, color c: SIMD4<Float>, aspect: Float) {
        let cosA = cos(angle)
        let sinA = sin(angle)
        func place(_ x: Float, _ y: Float) -> SIMD2<Float> {
            let rx = x * cosA - y * sinA
            let ry = x * sinA + y * cosA
            return SIMD2(position.x + rx / aspect, position.y + ry)
        }
        func tri(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ d: SIMD2<Float>) {
            vertices.append(VisualizerVertex(pos: a, color: c, size: 1))
            vertices.append(VisualizerVertex(pos: b, color: c, size: 1))
            vertices.append(VisualizerVertex(pos: d, color: c, size: 1))
        }

        switch cell {
        case .quad:
            let p0 = place(-size, -size), p1 = place(size, -size)
            let p2 = place(-size, size), p3 = place(size, size)
            tri(p0, p1, p2); tri(p1, p3, p2)
        case .bar:
            let w = size * 0.38, h = size * 2.4
            let p0 = place(-w, -h), p1 = place(w, -h)
            let p2 = place(-w, h), p3 = place(w, h)
            tri(p0, p1, p2); tri(p1, p3, p2)
        case .triangle:
            tri(place(0, size * 1.3), place(-size, -size * 0.8), place(size, -size * 0.8))
        case .diamond:
            let p0 = place(0, size * 1.5), p1 = place(size, 0)
            let p2 = place(0, -size * 1.5), p3 = place(-size, 0)
            tri(p0, p1, p3); tri(p1, p2, p3)
        case .shard:
            let w = size * 0.5
            tri(place(0, size * 2.0), place(-w, 0), place(w, 0))
            tri(place(0, -size * 1.2), place(-w, 0), place(w, 0))
        }
    }

    private func buildReplicator(_ spec: ReplicatorSpec, aspect: Float) {
        let bins = smoothedSpectrum.count
        let count = max(2, spec.count)
        for i in 0..<count {
            let t = Float(i) / Float(count - 1)
            let energy = smoothedSpectrum[min(bins - 1, i * bins / count)]

            // Sequence Replicator: a travelling wave of scale across elements,
            // so the pattern ripples rather than pulsing all at once.
            let seq = 0.5 + 0.5 * sin(phase * 3 - t * spec.sequenceOffset * .pi)
            let scale = spec.size * (energy * spec.sequence * 2.1) * (0.55 + 0.75 * seq)
            guard scale > 0.0005 else { continue }

            let position = layoutPosition(spec, index: i, t: t, energy: energy, aspect: aspect)
            // Radial layouts read better with cells facing outward.
            let angle: Float
            switch spec.layout {
            case .burst, .spiral, .ring: angle = atan2(position.y, position.x) - .pi / 2
            case .wave, .grid, .scatter: angle = seq * 0.6
            }
            addCell(spec.cell, at: position, size: scale, angle: angle,
                    color: color(at: t, alpha: 0.45 + energy * 0.7), aspect: aspect)
        }
    }

    // MARK: Simulation behaviors

    private func emitPosition(_ spec: ForceField, t: Float, index: Int) -> SIMD2<Float> {
        switch spec.emitLayout {
        case .ring, .burst, .spiral:
            let angle = t * 2 * .pi
            return SIMD2(cos(angle), sin(angle)) * spec.emitRadius
        case .wave:
            return SIMD2((t * 2 - 1) * spec.emitRadius, 1.0)
        case .grid, .scatter:
            return SIMD2(stableHash(index * 2) * 2 - 1, stableHash(index * 2 + 1) * 2 - 1)
                * spec.emitRadius
        }
    }

    /// Motion's forces, integrated per particle. Each term is one behavior:
    /// Vortex swirls around the centre, Orbit Around adds an inward bias so
    /// particles circle rather than fly off, Attractor pulls in, Repel pushes
    /// out, and Gravity, Wind, Drag and Random Motion do what they say.
    private func advanceSimulation(_ spec: ForceField, level: Float) {
        let spawn = Int(spec.rate * level * 2.6)
        if simParticles.count < 2400 && spawn > 0 {
            for k in 0..<spawn {
                let t = Float.random(in: 0...1)
                simParticles.append(Particle(
                    pos: emitPosition(spec, t: t, index: simParticles.count + k),
                    velocity: SIMD2(Float.random(in: -0.06...0.06), Float.random(in: -0.06...0.06)),
                    life: 1,
                    hue: t
                ))
            }
        }

        let dt: Float = 1.0 / 60.0
        let drive = 1 + bassEnvelope * 1.4
        for i in simParticles.indices {
            var particle = simParticles[i]
            let r = max(0.04, sqrt(particle.pos.x * particle.pos.x + particle.pos.y * particle.pos.y))
            let normal = SIMD2(particle.pos.x / r, particle.pos.y / r)
            let tangent = SIMD2(-normal.y, normal.x)

            var accel = SIMD2<Float>(0, 0)
            if spec.vortex != 0 { accel += tangent * (spec.vortex / r) }
            if spec.orbit != 0 { accel += (tangent - normal * 0.35) * spec.orbit }
            if spec.attractor != 0 { accel -= normal * spec.attractor }
            if spec.repel != 0 { accel += normal * (spec.repel / (r * r)) }
            if spec.gravity != 0 { accel.y -= spec.gravity }
            accel += spec.wind
            if spec.randomMotion != 0 {
                accel += SIMD2(Float.random(in: -1...1), Float.random(in: -1...1)) * spec.randomMotion
            }

            particle.velocity += accel * drive * dt
            particle.velocity *= (1 - spec.drag)
            particle.pos += particle.velocity * dt
            particle.life -= spec.lifetime
            simParticles[i] = particle
        }
        simParticles.removeAll { $0.life <= 0 || abs($0.pos.x) > 1.7 || abs($0.pos.y) > 1.7 }
    }

    // MARK: MilkDrop warp mesh

    private static let meshCols = 33
    private static let meshRows = 25

    /// MilkDrop's bass/mid/treb are normalised so that "typical" is 1.0, and
    /// presets depend on that — `sin(bass_att)` only behaves if bass_att
    /// hovers around one. A slow running average per band provides it.
    private func milkdropAudio(frame: VisualizerFrame) -> MilkdropAudio {
        func mean(_ range: Range<Int>) -> Double {
            let slice = smoothedSpectrum[range.clamped(to: smoothedSpectrum.indices)]
            guard !slice.isEmpty else { return 0 }
            return Double(slice.reduce(0, +)) / Double(slice.count)
        }
        let raw = SIMD3<Double>(mean(0..<16), mean(16..<41), mean(41..<64))
        bandAverages += (raw - bandAverages) * 0.002
        let floorLevel = SIMD3<Double>(repeating: 0.015)
        let safe = SIMD3<Double>(
            Swift.max(bandAverages.x, floorLevel.x),
            Swift.max(bandAverages.y, floorLevel.y),
            Swift.max(bandAverages.z, floorLevel.z)
        )
        let n = SIMD3<Double>(raw.x / safe.x, raw.y / safe.y, raw.z / safe.z)

        var audio = MilkdropAudio()
        audio.bass = Swift.min(4, n.x); audio.mid = Swift.min(4, n.y); audio.treb = Swift.min(4, n.z)
        audio.bassAtt = Swift.min(4, (n.x + 1) * 0.5)
        audio.midAtt = Swift.min(4, (n.y + 1) * 0.5)
        audio.trebAtt = Swift.min(4, (n.z + 1) * 0.5)
        audio.vol = (audio.bass + audio.mid + audio.treb) / 3
        audio.volAtt = (audio.bassAtt + audio.midAtt + audio.trebAtt) / 3
        return audio
    }

    /// Builds the warped mesh for this frame. The vertex stays put; its texture
    /// coordinate moves, which is how MilkDrop drags the previous frame around.
    private func buildWarpMesh(preset: MilkdropPreset, frame: VisualizerFrame) {
        elapsed += 1.0 / 60.0
        _ = preset.step(time: elapsed, fps: 60, audio: milkdropAudio(frame: frame))

        let cols = Self.meshCols
        let rows = Self.meshRows
        var points = [SIMD2<Float>](repeating: .zero, count: cols * rows)

        for r in 0..<rows {
            for c in 0..<cols {
                let x = Double(c) / Double(cols - 1)
                let y = Double(r) / Double(rows - 1)
                let m = preset.stepPixel(x: x, y: y)

                // MilkDrop's warp, in 0...1 texture space.
                var u = x - m.cx
                var v = y - m.cy
                let cosR = cos(m.rot), sinR = sin(m.rot)
                let ur = u * cosR - v * sinR
                let vr = u * sinR + v * cosR
                let zoom = Swift.max(0.001, m.zoom)
                u = ur / zoom / Swift.max(0.001, m.sx)
                v = vr / zoom / Swift.max(0.001, m.sy)
                u += m.cx - m.dx
                v += m.cy - m.dy
                points[r * cols + c] = SIMD2(Float(u), Float(v))
            }
        }

        warpVertices.removeAll(keepingCapacity: true)
        func vertex(_ c: Int, _ r: Int) -> WarpVertex {
            let x = Float(c) / Float(cols - 1)
            let y = Float(r) / Float(rows - 1)
            return WarpVertex(pos: SIMD2(x * 2 - 1, 1 - y * 2), uv: points[r * cols + c])
        }
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let a = vertex(c, r), b = vertex(c + 1, r)
                let d = vertex(c, r + 1), e = vertex(c + 1, r + 1)
                warpVertices.append(contentsOf: [a, b, d, b, e, d])
            }
        }

        let needed = warpVertices.count * MemoryLayout<WarpVertex>.stride
        if warpBuffer == nil || warpCapacity < needed {
            warpBuffer = device.makeBuffer(length: needed, options: .storageModeShared)
            warpCapacity = needed
        }
        warpBuffer?.contents().copyMemory(from: warpVertices, byteCount: needed)
    }

    private func ensureBuffer(count: Int) -> MTLBuffer? {
        if let buffer = vertexBuffer, count <= vertexCapacity { return buffer }
        let capacity = max(count, vertexCapacity * 2, 4096)
        guard let created = device.makeBuffer(
            length: capacity * MemoryLayout<VisualizerVertex>.stride,
            options: .storageModeShared
        ) else { return nil }
        vertexBuffer = created
        vertexCapacity = capacity
        return created
    }
}

// MARK: - NSViewRepresentable

/// Lets the window's buttons reach the renderer, which SwiftUI otherwise only
/// talks to through `updateNSView`.
final class VisualizerController {
    fileprivate(set) weak var renderer: VisualizerRenderer?

    func next() { renderer?.nextPreset() }
    func previous() { renderer?.previousPreset() }
    var presetName: String { renderer?.activePresetName ?? "" }
}

private struct MetalVisualizerView: NSViewRepresentable {
    let mode: VisualizerMode
    let milkdrop: MilkdropPreset?
    let milkdropPool: [MilkdropPreset]
    let dwell: Float
    let isLocked: Bool
    let controller: VisualizerController
    let frameProvider: () -> VisualizerFrame
    let onPresetChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: VisualizerRenderer?
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.035, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        if let device = view.device,
           let renderer = VisualizerRenderer(device: device, pixelFormat: view.colorPixelFormat) {
            context.coordinator.renderer = renderer
            controller.renderer = renderer
            configure(renderer)
            view.delegate = renderer
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        controller.renderer = renderer
        configure(renderer)
    }

    private func configure(_ renderer: VisualizerRenderer) {
        renderer.frameProvider = frameProvider
        renderer.onPresetChange = onPresetChange
        renderer.milkdrop = milkdrop
        renderer.milkdropPool = milkdropPool
        renderer.dwell = dwell
        renderer.isLocked = isLocked
        // Last: switching to Auto picks a preset, which needs the pool above.
        renderer.mode = mode
    }
}

// MARK: - Window contents

struct VisualizerWindow: View {
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var milkdropLibrary: MilkdropLibrary
    @AppStorage(VisualizerMode.storageKey) private var storedMode = VisualizerMode.auto.rawValue
    @AppStorage(MilkdropLibrary.selectionKey) private var storedMilkdrop = ""
    @AppStorage("visualizerDwell") private var dwell = 30.0
    @AppStorage("visualizerShuffleMilkdrop") private var shuffleMilkdrop = true
    @AppStorage("visualizerLastManualMode") private var lastManualMode = VisualizerMode.plasma.rawValue
    @State private var isLocked = false
    @State private var showChrome = true
    @State private var presetName = ""
    @State private var showTitle = false
    @State private var hideTask: Task<Void, Never>?
    @State private var titleTask: Task<Void, Never>?
    @State private var controller = VisualizerController()

    private var mode: VisualizerMode {
        VisualizerMode(rawValue: storedMode) ?? .auto
    }

    private var title: String {
        switch mode {
        case .auto: return presetName
        case .milkdrop: return storedMilkdrop.isEmpty ? "MilkDrop" : storedMilkdrop
        default: return mode.rawValue
        }
    }

    private var subtitle: String {
        switch mode {
        case .auto: return isLocked ? "Shuffle · held" : "Shuffle"
        case .milkdrop: return "MilkDrop"
        default: return mode.family
        }
    }

    var body: some View {
        ZStack {
            if MTLCreateSystemDefaultDevice() == nil {
                Text("No Metal device available on this Mac.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                MetalVisualizerView(
                    mode: mode,
                    milkdrop: mode == .milkdrop ? milkdropLibrary.presets.first(where: { $0.name == storedMilkdrop }) : nil,
                    milkdropPool: shuffleMilkdrop ? milkdropLibrary.presets : [],
                    dwell: Float(dwell),
                    isLocked: isLocked,
                    controller: controller,
                    frameProvider: { engine.visualizerFrame() },
                    onPresetChange: { name in
                        // Reported from inside the draw call; hop out of it
                        // before touching view state.
                        DispatchQueue.main.async { announce(name) }
                    }
                )
                .ignoresSafeArea()
            }

            if !engine.isRunning {
                // Some modes leave a still picture in silence; dim it so the
                // notice reads over whatever is there.
                Color.black.opacity(0.6).ignoresSafeArea()
                stoppedNotice
            }

            VStack {
                HStack {
                    if showTitle || showChrome, !title.isEmpty {
                        titleCard.transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    Spacer()
                }
                Spacer()
                if showChrome {
                    controlBar.transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(18)

            shortcuts
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if !showChrome {
                    withAnimation(.easeOut(duration: 0.15)) { showChrome = true }
                }
                scheduleHide()
            case .ended:
                scheduleHide()
            }
        }
        .onAppear {
            presetName = controller.presetName
            scheduleHide()
        }
        .onChange(of: storedMode) { _, newValue in
            if let picked = VisualizerMode(rawValue: newValue), picked != .auto, picked != .milkdrop {
                lastManualMode = newValue
            }
            presetName = controller.presetName
            flashTitle()
        }
        .onDisappear {
            hideTask?.cancel()
            titleTask?.cancel()
        }
    }

    // MARK: Pieces

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subtitle.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.6))
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.7), radius: 6, y: 1)
        .allowsHitTesting(false)
    }

    private var stoppedNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
            Text("The visualizer follows the audio")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("Start the engine and play something.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Button("Start Engine") { engine.start() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.mint)
                .controlSize(.large)
        }
        .padding(28)
    }

    private var controlBar: some View {
        HStack(spacing: 6) {
            barButton("backward.fill", help: "Previous  ←") { step(-1) }

            Menu {
                Button {
                    storedMode = VisualizerMode.auto.rawValue
                } label: {
                    Label("Shuffle everything", systemImage: "shuffle")
                }
                Divider()
                ForEach(VisualizerMode.groups) { group in
                    Menu(group.id) {
                        ForEach(group.modes) { m in
                            Button(m.rawValue) { storedMode = m.rawValue }
                        }
                    }
                }
                if !milkdropLibrary.isEmpty {
                    Divider()
                    Menu("MilkDrop (\(milkdropLibrary.presets.count))") {
                        ForEach(milkdropLibrary.presets.prefix(60), id: \.name) { preset in
                            Button(preset.name) {
                                storedMilkdrop = preset.name
                                storedMode = VisualizerMode.milkdrop.rawValue
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: mode == .auto ? "shuffle" : "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text(title.isEmpty ? mode.rawValue : title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 150)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            barButton("forward.fill", help: "Next  →  or Space") { step(1) }

            Divider().frame(height: 18).padding(.horizontal, 4)

            barButton("shuffle", active: mode == .auto, help: "Shuffle  S") { toggleShuffle() }
            barButton(isLocked ? "lock.fill" : "lock.open", active: isLocked,
                      help: "Hold this one  L") { isLocked.toggle() }
                .disabled(mode != .auto)

            Menu {
                Section("Change every") {
                    ForEach([10.0, 20.0, 30.0, 60.0, 120.0, 300.0], id: \.self) { seconds in
                        Button {
                            dwell = seconds
                        } label: {
                            if dwell == seconds {
                                Label(Self.dwellLabel(seconds), systemImage: "checkmark")
                            } else {
                                Text(Self.dwellLabel(seconds))
                            }
                        }
                    }
                }
                if !milkdropLibrary.isEmpty {
                    Divider()
                    Toggle("Include MilkDrop presets", isOn: $shuffleMilkdrop)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(Self.dwellLabel(dwell))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("How long each visualization plays")

            Divider().frame(height: 18).padding(.horizontal, 4)

            barButton("arrow.up.left.and.arrow.down.right", help: "Full screen  F") { toggleFullScreen() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 4)
        .padding(.bottom, 8)
    }

    private func barButton(_ symbol: String, active: Bool = false, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Theme.cyan : Color.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(Circle().fill(active ? Theme.cyan.opacity(0.16) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Keyboard control that works whether or not the bar is showing: these
    /// stay in the hierarchy, invisible, so their shortcuts stay live.
    private var shortcuts: some View {
        Group {
            Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { step(1) }.keyboardShortcut(.space, modifiers: [])
            Button("") { toggleShuffle() }.keyboardShortcut("s", modifiers: [])
            Button("") { if mode == .auto { isLocked.toggle(); flashTitle() } }.keyboardShortcut("l", modifiers: [])
            Button("") { toggleFullScreen() }.keyboardShortcut("f", modifiers: [])
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private static func dwellLabel(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds))s" : "\(Int(seconds / 60))m"
    }

    /// In shuffle, steps through the shuffle's history; with a mode chosen by
    /// hand, steps through the list of modes.
    private func step(_ direction: Int) {
        if mode == .auto {
            direction > 0 ? controller.next() : controller.previous()
            return
        }
        let list = VisualizerMode.selectable
        let current = list.firstIndex(of: mode) ?? 0
        let next = (current + direction + list.count) % list.count
        storedMode = list[next].rawValue
    }

    private func toggleShuffle() {
        storedMode = mode == .auto ? lastManualMode : VisualizerMode.auto.rawValue
    }

    private func toggleFullScreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }

    private func announce(_ name: String) {
        presetName = name
        flashTitle()
    }

    /// Names the visualization for a few seconds whenever it changes.
    private func flashTitle() {
        withAnimation(.easeOut(duration: 0.3)) { showTitle = true }
        titleTask?.cancel()
        titleTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.8)) { showTitle = false }
        }
    }

    /// The controls get in the way of a full-screen visual, so they fade out
    /// when the pointer stops moving.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) { showChrome = false }
        }
    }
}
