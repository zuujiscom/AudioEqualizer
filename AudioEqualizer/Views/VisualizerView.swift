import SwiftUI
import MetalKit
import simd

// MARK: - Modes

enum VisualizerMode: String, CaseIterable, Identifiable {
    /// Cycles `VisualizerPreset.rotation` on a timer, switching on a beat.
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
    // Simulation — emitters driven by Motion-style forces
    case orbitals = "Orbitals"
    case swarm = "Swarm"
    case cascade = "Cascade"
    // Shader — computed per pixel on the GPU
    case plasma = "Plasma"
    case kaleidoscope = "Kaleidoscope"
    case aurora = "Aurora"
    case nebula = "Nebula"
    case metaballs = "Metaballs"
    case warp = "Warp"

    var id: String { rawValue }

    /// Point-sprite modes draw additively; the rest draw opaque geometry.
    var isParticle: Bool {
        switch self {
        case .bloom, .starfield, .matrix, .orbitals, .swarm, .cascade: return true
        default: return false
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
        default:
            return nil
        }
    }

    /// Full-screen fragment-shader modes: no CPU geometry at all.
    var isProcedural: Bool { proceduralIndex != nil }

    var proceduralIndex: Int32? {
        switch self {
        case .plasma: return 0
        case .kaleidoscope: return 1
        case .aurora: return 2
        case .nebula: return 3
        case .metaballs: return 4
        case .warp: return 5
        default: return nil
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
        case .burst, .helix, .waveform, .grid, .scatter:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.008, rot: 0.003,
                                    warp: 0.4, decay: 0.90)
        case .orbitals, .swarm, .cascade:
            return VisualizerPreset(name: mode.rawValue, mode: mode, zoom: 1.012, rot: 0.004,
                                    decay: 0.93)
        default:
            return VisualizerPreset(name: mode.rawValue, mode: mode, decay: 0)
        }
    }

    /// The Auto rotation. Deliberately varied: tunnels, spirals, drifts and
    /// layered shader beds, so consecutive presets do not look alike.
    static let rotation: [VisualizerPreset] = [
        VisualizerPreset(name: "Vortex", mode: .radial, zoom: 1.03, rot: 0.013, warp: 0.6, decay: 0.94),
        VisualizerPreset(name: "Deep Tunnel", mode: .tunnel, zoom: 1.045, rot: -0.006, decay: 0.93, paletteShift: 0.3),
        VisualizerPreset(name: "Silk", mode: .lissajous, zoom: 1.006, rot: 0.011, warp: 1.4, decay: 0.96, paletteShift: 0.6),
        VisualizerPreset(name: "Ion Storm", mode: .bloom, zoom: 1.028, rot: -0.014, warp: 0.9, decay: 0.95),
        VisualizerPreset(name: "Rainfall", mode: .matrix, zoom: 0.995, dy: 0.6, decay: 0.90, paletteShift: 0.45),
        VisualizerPreset(name: "Hyperspace", mode: .starfield, zoom: 1.05, rot: 0.004, decay: 0.94, paletteShift: 0.15),
        VisualizerPreset(name: "Liquid Bars", mode: .mirror, zoom: 1.016, warp: 1.6, decay: 0.92, paletteShift: 0.7),
        VisualizerPreset(name: "Aurora Drift", mode: .aurora, decay: 0.88, paletteShift: 0.2, overlayAlpha: 0.45),
        VisualizerPreset(name: "Nebula Bloom", mode: .nebula, zoom: 1.02, rot: 0.005, decay: 0.90, overlayAlpha: 0.35),
        VisualizerPreset(name: "Kaleido Spin", mode: .kaleidoscope, zoom: 1.01, rot: -0.018, decay: 0.85, overlayAlpha: 0.5),
        VisualizerPreset(name: "Plasma Wash", mode: .plasma, zoom: 1.008, warp: 1.1, decay: 0.86, paletteShift: 0.55, overlayAlpha: 0.4),
        VisualizerPreset(name: "Warp Core", mode: .warp, zoom: 1.015, rot: 0.007, decay: 0.87, overlayAlpha: 0.5),
        VisualizerPreset(name: "Metaflow", mode: .metaballs, zoom: 1.012, rot: -0.004, warp: 0.8, decay: 0.88, overlayAlpha: 0.45),
        VisualizerPreset(name: "Ribbon Trails", mode: .ribbon, zoom: 1.01, rot: 0.009, warp: 1.2, decay: 0.95, paletteShift: 0.35),
        VisualizerPreset(name: "Slow Burn", mode: .scope, zoom: 1.002, rot: -0.003, warp: 1.8, decay: 0.97, paletteShift: 0.8),
        // Replicators and simulations
        VisualizerPreset(name: "Sunburst", mode: .burst, zoom: 1.018, rot: 0.006, warp: 0.5, decay: 0.93, paletteShift: 0.25),
        VisualizerPreset(name: "Double Helix", mode: .helix, zoom: 1.01, rot: -0.012, warp: 0.7, decay: 0.94, paletteShift: 0.5),
        VisualizerPreset(name: "Signal Wave", mode: .waveform, zoom: 1.006, warp: 1.0, dx: 0.4, decay: 0.94, paletteShift: 0.65),
        VisualizerPreset(name: "Lattice", mode: .grid, zoom: 1.022, rot: 0.008, decay: 0.90, paletteShift: 0.15),
        VisualizerPreset(name: "Confetti", mode: .scatter, zoom: 1.014, rot: -0.007, warp: 1.3, decay: 0.92, paletteShift: 0.85),
        VisualizerPreset(name: "Orbit Cloud", mode: .orbitals, zoom: 1.02, rot: 0.005, warp: 0.6, decay: 0.95),
        VisualizerPreset(name: "Swarm", mode: .swarm, zoom: 1.016, rot: -0.009, warp: 0.9, decay: 0.95, paletteShift: 0.4),
        VisualizerPreset(name: "Downpour", mode: .cascade, zoom: 0.997, dy: 0.5, decay: 0.93, paletteShift: 0.7)
    ]
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

/// Matches `Uniforms` in the shader: twelve floats then an int, 52-byte stride.
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
    var mode: Int32
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VIn { float2 pos; float4 color; float size; };
struct VOut { float4 position [[position]]; float4 color; float pointSize [[point_size]]; };

struct Uniforms {
    float time;
    float bass;
    float level;
    float aspect;
    float decay;
    float zoom;
    float rot;
    float warp;
    float dx;
    float dy;
    float paletteShift;
    float overlayAlpha;
    int mode;
};

struct FS { float4 position [[position]]; float2 uv; };

// --- CPU geometry ---

vertex VOut v_main(const device VIn* verts [[buffer(0)]], uint vid [[vertex_id]]) {
    VOut o;
    o.position = float4(verts[vid].pos, 0.0, 1.0);
    o.color = verts[vid].color;
    o.pointSize = verts[vid].size;
    return o;
}

fragment float4 f_solid(VOut in [[stage_in]]) {
    return in.color;
}

fragment float4 f_point(VOut in [[stage_in]], float2 pc [[point_coord]]) {
    float d = length(pc - float2(0.5, 0.5));
    // Two-lobe falloff: a tight core inside a wide halo reads as glow.
    float core = smoothstep(0.5, 0.0, d);
    float halo = smoothstep(0.5, 0.15, d);
    return float4(in.color.rgb, in.color.a * (core * 0.55 + halo * 0.75));
}

// --- Full-screen passes ---

vertex FS v_full(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    FS o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    // Flip y so uv matches Metal's top-left texture origin.
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

/// The heart of the classic look: the previous frame is re-sampled through a
/// zoom / rotate / drift / ripple transform and dimmed, rather than simply
/// faded. Feeding a moving copy of the last frame back in is what turns plain
/// geometry into tunnels, spirals and smears.
fragment float4 f_feedback(FS in [[stage_in]],
                           constant Uniforms& u [[buffer(0)]],
                           texture2d<float> prev [[texture(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);

    float2 p = in.uv - 0.5;
    p.x *= u.aspect;

    float c = cos(u.rot);
    float sn = sin(u.rot);
    p = float2(p.x * c - p.y * sn, p.x * sn + p.y * c);

    p /= max(0.01, u.zoom);

    // Ripple, scaled by bass so the warp breathes with the track.
    float w = u.warp * (0.6 + u.bass * 1.6);
    p += w * 0.02 * float2(sin(p.y * 7.0 + u.time * 1.3),
                           cos(p.x * 7.0 - u.time * 1.1));

    p += float2(u.dx, u.dy) * 0.01;

    p.x /= u.aspect;
    float2 uv = p + 0.5;

    float3 col = prev.sample(smp, uv).rgb * u.decay;

    // Bleed the hue along slightly so long trails drift in colour.
    col = mix(col, col.gbr, 0.012 * u.paletteShift);
    return float4(col, 1.0);
}

struct WarpIn { float2 pos; float2 uv; };
struct WarpOut { float4 position [[position]]; float2 uv; };

/// MilkDrop warps a mesh rather than applying one transform to the whole
/// frame: every vertex carries its own sample point, computed from that
/// preset's per-pixel equations. Sampling the previous frame through the mesh
/// is what makes an imported preset move the way it does in MilkDrop.
vertex WarpOut v_warpmesh(const device WarpIn* verts [[buffer(0)]], uint vid [[vertex_id]]) {
    WarpOut o;
    o.position = float4(verts[vid].pos, 0.0, 1.0);
    o.uv = verts[vid].uv;
    return o;
}

fragment float4 f_warpmesh(WarpOut in [[stage_in]],
                           constant Uniforms& u [[buffer(0)]],
                           texture2d<float> prev [[texture(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);
    return float4(prev.sample(smp, in.uv).rgb * u.decay, 1.0);
}

fragment float4 f_composite(FS in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);
    float3 c = tex.sample(smp, in.uv).rgb;
    // Gentle filmic lift so bright cores bloom instead of clipping flat.
    c = c / (c + 0.75) * 1.75;
    return float4(c, 1.0);
}

// --- Helpers ---

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1.0, 0.0)), u.x),
               mix(hash21(i + float2(0.0, 1.0)), hash21(i + float2(1.0, 1.0)), u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p *= 2.02;
        a *= 0.5;
    }
    return v;
}

/// Cosine gradient palette — smooth, saturated, and cheap.
static float3 palette(float t, float shift) {
    float3 d = float3(0.0, 0.33, 0.67) + shift;
    return 0.5 + 0.5 * cos(6.28318 * (t + d));
}

static float bandAt(const device float* spectrum, float x) {
    float f = clamp(x, 0.0, 0.9999) * 63.0;
    int i = int(f);
    return mix(spectrum[i], spectrum[min(i + 1, 63)], fract(f));
}

// --- Procedural modes ---

fragment float4 f_procedural(FS in [[stage_in]],
                             constant Uniforms& u [[buffer(0)]],
                             const device float* spectrum [[buffer(1)]]) {
    float2 uv = in.uv;
    float2 p = (uv - 0.5) * float2(u.aspect, 1.0);
    float t = u.time;
    float3 col = float3(0.0);

    if (u.mode == 0) {
        // Plasma: interfering waves, pushed around by bass.
        float2 q = p * 3.0;
        float v = sin(q.x + t)
                + sin(q.y * 1.3 + t * 0.9)
                + sin((q.x + q.y) * 0.8 + t * 1.3)
                + sin(length(q) * 2.0 - t * 1.7 * (1.0 + u.bass));
        v *= 0.25;
        float band = bandAt(spectrum, uv.x);
        col = palette(v * 0.5 + t * 0.02, u.paletteShift) * (0.35 + u.level * 1.1 + band * 0.9);
    } else if (u.mode == 1) {
        // Kaleidoscope: fold the plane into wedges, then ring it by spectrum.
        float r = length(p);
        float a = atan2(p.y, p.x);
        float seg = 6.28318 / 10.0;
        a = abs(fmod(a + t * 0.15 + 100.0 * seg, seg) - seg * 0.5);
        float2 q = float2(cos(a), sin(a)) * r;
        float band = bandAt(spectrum, r * 1.7);
        float pattern = 0.5 + 0.5 * sin(q.x * 26.0 - t * 2.0 + band * 10.0);
        float rings = 0.5 + 0.5 * sin(r * 34.0 - t * 3.0);
        col = palette(r * 1.4 + t * 0.05, 0.2 + u.paletteShift) * (0.2 + band * 2.4) * (0.45 + 0.55 * pattern * rings);
        col *= smoothstep(1.05, 0.1, r);
    } else if (u.mode == 2) {
        // Aurora: drifting curtains whose height follows the spectrum.
        float y = 1.0 - uv.y;
        float band = bandAt(spectrum, uv.x);
        float n = fbm(float2(uv.x * 3.0, y * 1.6 - t * 0.22));
        float crest = 0.18 + n * 0.42 + band * 0.55;
        float glow = exp(-abs(y - crest) * 7.5);
        float veil = exp(-abs(y - crest * 0.6) * 3.0) * 0.35;
        col = palette(uv.x * 0.6 + t * 0.03, 0.35 + u.paletteShift) * (glow + veil) * (0.8 + u.level * 2.0);
        col += float3(0.02, 0.05, 0.12) * (1.0 - y);
    } else if (u.mode == 3) {
        // Nebula: domain-warped noise, breathing on bass.
        float2 q = p * 2.2;
        float tt = t * 0.06;
        float warp = fbm(q * 0.8 - tt);
        float n = fbm(q * 1.5 + float2(tt, -tt) + warp * 1.2);
        float d = length(q);
        col = palette(n + u.bass * 0.3, 0.5 + u.paletteShift) * pow(n, 2.0) * 2.6;
        col *= smoothstep(1.7, 0.1, d);
        col += palette(n, 0.5) * u.bass * 0.6 * exp(-d * 2.0);
    } else if (u.mode == 4) {
        // Metaballs: seven blobs, each swollen by its own band.
        float2 q = p * 2.0;
        float field = 0.0;
        for (int i = 0; i < 7; i++) {
            float fi = float(i);
            float band = spectrum[int(fi * 9.0)];
            float ang = t * (0.3 + fi * 0.07) + fi * 1.7;
            float2 c = float2(cos(ang), sin(ang * 1.3)) * (0.3 + 0.4 * sin(t * 0.2 + fi));
            float rad = 0.10 + band * 0.38 + u.bass * 0.06;
            float2 delta = q - c;
            field += (rad * rad) / max(1e-4, dot(delta, delta));
        }
        float m = smoothstep(0.75, 1.7, field);
        float edge = smoothstep(1.7, 0.95, field);
        col = palette(field * 0.22 + t * 0.03, 0.15 + u.paletteShift) * m * (0.7 + u.level);
        col += palette(field * 0.22, 0.15) * edge * 0.5;
    } else {
        // Warp: a tunnel, with the throttle on bass.
        float r = max(0.02, length(p));
        float a = atan2(p.y, p.x);
        float z = 0.35 / r + t * 0.6 * (1.0 + u.bass * 0.8);
        float band = bandAt(spectrum, fract(z * 0.15));
        float stripes = 0.5 + 0.5 * sin(z * 6.0 + sin(a * 5.0 + t) * 1.2);
        col = palette(fract(z * 0.08), 0.6 + u.paletteShift) * stripes * (0.25 + band * 2.2);
        col *= smoothstep(0.0, 0.22, r) * smoothstep(1.25, 0.28, r);
    }

    return float4(col, u.overlayAlpha);
}
"""

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
    var mode: VisualizerMode = .bars
    /// Set by the view; called on the main thread each frame.
    var frameProvider: (() -> VisualizerFrame)?
    /// Reports the Auto rotation's current preset so the chrome can name it.
    var onPresetChange: ((String) -> Void)?

    private let commandQueue: MTLCommandQueue
    private let solidPipeline: MTLRenderPipelineState
    private let pointPipeline: MTLRenderPipelineState
    private let feedbackPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let proceduralPipeline: MTLRenderPipelineState
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

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let uniformBuffer: MTLBuffer
    private let spectrumBuffer: MTLBuffer

    /// Geometry accumulates here instead of straight into the drawable: the
    /// swap chain rotates through several drawables, so "last frame" only
    /// exists if we keep it ourselves. This is what makes trails possible.
    private var accumTextures: [MTLTexture] = []
    private var accumIndex = 0
    private var accumNeedsClear = true

    /// Auto-cycle state.
    private var presetIndex = 0
    private var presetElapsed: Float = 0
    private var beatHold: Float = 0

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: shaderSource, options: nil),
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
                                               options: .storageModeShared)
        else { return nil }

        self.device = device
        self.pixelFormat = pixelFormat
        commandQueue = queue
        uniformBuffer = uniforms
        spectrumBuffer = spectrum

        func pipeline(_ vertex: MTLFunction, _ fragment: MTLFunction, blend: BlendMode) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertex
            desc.fragmentFunction = fragment
            guard let attachment = desc.colorAttachments[0] else { return nil }
            attachment.pixelFormat = pixelFormat
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
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        guard let solid = pipeline(vfn, solidFn, blend: .alpha),
              let point = pipeline(vfn, pointFn, blend: .additive),
              let feedback = pipeline(vfull, feedbackFn, blend: .none),
              let comp = pipeline(vfull, compFn, blend: .none),
              let proc = pipeline(vfull, procFn, blend: .alpha),
              let warpMesh = pipeline(warpVFn, warpFFn, blend: .none) else { return nil }

        solidPipeline = solid
        pointPipeline = point
        feedbackPipeline = feedback
        compositePipeline = comp
        proceduralPipeline = proc
        warpMeshPipeline = warpMesh
        super.init()
    }

    private enum BlendMode { case none, alpha, additive }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        accumTextures = []
    }

    /// The preset actually being rendered: the Auto rotation when Auto is
    /// selected, otherwise the standard feedback for the chosen mode.
    private var activePreset: VisualizerPreset {
        mode == .auto
            ? VisualizerPreset.rotation[presetIndex % VisualizerPreset.rotation.count]
            : VisualizerPreset.standard(for: mode)
    }

    var activePresetName: String { activePreset.name }

    /// Hold each preset for a good while, then hard-cut on the next beat so the
    /// change lands with the music rather than at an arbitrary moment. Long
    /// dwells matter: the feedback buffer needs time to build up depth, and a
    /// preset cut short never gets to show what it does.
    private func advanceAutoCycle(rising: Float) {
        guard mode == .auto else {
            presetElapsed = 0
            return
        }
        presetElapsed += 1.0 / 60.0
        beatHold = max(0, beatHold - 1.0 / 60.0)

        // Roughly a minute per preset. Because the cut waits for a beat, the
        // real dwell is usually close to the minimum rather than the maximum.
        let minimumHold: Float = 55
        let forcedHold: Float = 100
        let beat = rising > 0.06 && beatHold <= 0

        if presetElapsed > forcedHold || (presetElapsed > minimumHold && beat) {
            presetIndex = (presetIndex + 1) % VisualizerPreset.rotation.count
            onPresetChange?(activePreset.name)
            presetElapsed = 0
            beatHold = 0.4
            accumNeedsClear = true
            particles.removeAll(keepingCapacity: true)
            stars.removeAll(keepingCapacity: true)
            drops.removeAll(keepingCapacity: true)
        }
    }

    /// Two textures: the warp pass reads one and writes the other, so a frame
    /// can never sample the target it is drawing into.
    private func ensureAccum(size: CGSize) -> Bool {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        if accumTextures.count == 2,
           accumTextures[0].width == width, accumTextures[0].height == height {
            return true
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false
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
              ensureAccum(size: view.drawableSize),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let frame = frameProvider?() ?? VisualizerFrame(
            waveform: [Float](repeating: 0, count: 256),
            spectrum: [Float](repeating: 0, count: 64),
            bass: 0, level: 0
        )

        let aspect = Float(view.drawableSize.width / max(1, view.drawableSize.height))
        advance(frame: frame)

        let preset = activePreset
        let effectiveMode = preset.mode
        uploadUniforms(aspect: aspect, frame: frame, preset: preset)

        let source = accumTextures[accumIndex]
        let target = accumTextures[1 - accumIndex]

        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = target
        scenePass.colorAttachments[0].loadAction = .dontCare
        scenePass.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePass) {
            // 1 — warp and dim the previous frame into the target.
            if let preset = milkdrop {
                buildWarpMesh(preset: preset, frame: frame)
                if !accumNeedsClear, let mesh = warpBuffer, !warpVertices.isEmpty {
                    encoder.setRenderPipelineState(warpMeshPipeline)
                    encoder.setVertexBuffer(mesh, offset: 0, index: 0)
                    encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                    encoder.setFragmentTexture(source, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: warpVertices.count)
                }
            } else {
                encoder.setRenderPipelineState(feedbackPipeline)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(accumNeedsClear ? nil : source, index: 0)
                if !accumNeedsClear {
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                }
            }
            accumNeedsClear = false

            // 2 — draw this frame's content over it.
            if effectiveMode.isProcedural {
                encoder.setRenderPipelineState(proceduralPipeline)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(spectrumBuffer, offset: 0, index: 1)
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
                    encoder.drawPrimitives(
                        type: effectiveMode.isParticle ? .point : .triangle,
                        vertexStart: 0,
                        vertexCount: vertices.count
                    )
                }
            }
            encoder.endEncoding()
        }

        // 3 — tone-map onto the drawable.
        if let present = view.currentRenderPassDescriptor {
            present.colorAttachments[0].loadAction = .dontCare
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: present) {
                encoder.setRenderPipelineState(compositePipeline)
                encoder.setFragmentTexture(target, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }
        }

        accumIndex = 1 - accumIndex
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func uploadUniforms(aspect: Float, frame: VisualizerFrame, preset: VisualizerPreset) {
        var uniforms = VisualizerUniforms(
            time: phase * 4,
            bass: bassEnvelope,
            level: frame.level,
            aspect: aspect,
            decay: preset.decay,
            zoom: preset.zoom,
            rot: preset.rot,
            warp: preset.warp,
            dx: preset.dx,
            dy: preset.dy,
            paletteShift: preset.paletteShift,
            overlayAlpha: preset.overlayAlpha,
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
        phase += 0.012 * min(3.0, audioMotion * 3.4)

        // Attack fast, release slow: a kick should snap and then fall away.
        for i in smoothedSpectrum.indices where i < frame.spectrum.count {
            let target = frame.spectrum[i]
            let rate: Float = target > smoothedSpectrum[i] ? 0.55 : 0.12
            smoothedSpectrum[i] += (target - smoothedSpectrum[i]) * rate
        }

        bassEnvelope += (frame.bass - bassEnvelope) * (frame.bass > bassEnvelope ? 0.6 : 0.08)
        let rising = max(0, frame.bass - lastBass)
        lastBass = frame.bass

        advanceAutoCycle(rising: rising)
        let active = activePreset.mode

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

    private func color(at t: Float, alpha: Float = 1) -> SIMD4<Float> {
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
                size: base + fade * growth + bassEnvelope * 12
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
                size: 1.5 + distance * 7 + bassEnvelope * 10
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

private struct MetalVisualizerView: NSViewRepresentable {
    let mode: VisualizerMode
    let milkdrop: MilkdropPreset?
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
            renderer.mode = mode
            renderer.milkdrop = milkdrop
            renderer.frameProvider = frameProvider
            renderer.onPresetChange = onPresetChange
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.mode = mode
        context.coordinator.renderer?.milkdrop = milkdrop
        context.coordinator.renderer?.frameProvider = frameProvider
        context.coordinator.renderer?.onPresetChange = onPresetChange
    }
}

// MARK: - Window contents

struct VisualizerWindow: View {
    @EnvironmentObject private var engine: AudioEngine
    @AppStorage(VisualizerMode.storageKey) private var storedMode = VisualizerMode.bars.rawValue
    @AppStorage(MilkdropLibrary.selectionKey) private var storedMilkdrop = ""
    @EnvironmentObject private var milkdropLibrary: MilkdropLibrary
    @State private var showChrome = true
    @State private var presetName = ""
    @State private var hideTask: Task<Void, Never>?

    private var mode: VisualizerMode {
        VisualizerMode(rawValue: storedMode) ?? .bars
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if MTLCreateSystemDefaultDevice() == nil {
                Text("No Metal device available on this Mac.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                MetalVisualizerView(
                    mode: mode,
                    milkdrop: mode == .milkdrop ? milkdropLibrary.presets.first(where: { $0.name == storedMilkdrop }) : nil,
                    frameProvider: { engine.visualizerFrame() },
                    onPresetChange: { presetName = $0 }
                )
                .ignoresSafeArea()
            }

            if showChrome {
                HStack(spacing: 12) {
                    Picker("", selection: $storedMode) {
                        Text(VisualizerMode.auto.rawValue).tag(VisualizerMode.auto.rawValue)
                        Divider()
                        ForEach(VisualizerMode.groups) { group in
                            Section(group.id) {
                                ForEach(group.modes) { m in
                                    Text(m.rawValue).tag(m.rawValue)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)

                    if mode == .milkdrop && !storedMilkdrop.isEmpty {
                        Text(storedMilkdrop)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if mode == .auto && !presetName.isEmpty {
                        Text(presetName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if !engine.isRunning {
                        Text("Engine stopped")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 22)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(Color.black)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                withAnimation(.easeOut(duration: 0.15)) { showChrome = true }
                scheduleHide()
            case .ended:
                scheduleHide()
            }
        }
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
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
