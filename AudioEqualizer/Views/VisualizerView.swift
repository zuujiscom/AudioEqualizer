import SwiftUI
import MetalKit
import simd

// MARK: - Modes

enum VisualizerMode: String, CaseIterable, Identifiable {
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
        self == .bloom || self == .starfield || self == .matrix
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

    /// How much of the previous frame is erased each tick. Low values leave
    /// long light-trails, which is most of what makes a visualizer read as
    /// "glowing" rather than as a bar chart.
    var trailFade: Float {
        switch self {
        case .bars, .mirror: return 0.70
        case .radial: return 0.30
        case .tunnel: return 0.22
        case .scope, .ribbon: return 0.13
        case .lissajous: return 0.07
        case .bloom, .starfield: return 0.09
        case .matrix: return 0.16
        default: return 1
        }
    }

    /// ⌘⌥1…⌘⌥9 then ⌘⌥0 for the first ten; the rest are click-only.
    var shortcut: KeyEquivalent? {
        guard let index = Self.allCases.firstIndex(of: self) else { return nil }
        let digits: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        return index < digits.count ? digits[index] : nil
    }

    var family: String {
        if isProcedural { return "Shader" }
        return isParticle ? "Particles" : "Geometric"
    }

    /// Shared with `VisualizerWindow`'s `@AppStorage`, so picking a mode from
    /// the menu moves an already-open window too.
    static let storageKey = "visualizerMode"

    static var groups: [VisualizerModeGroup] {
        ["Geometric", "Particles", "Shader"].map { family in
            VisualizerModeGroup(id: family, modes: allCases.filter { $0.family == family })
        }
    }
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

/// Matches `Uniforms` in the shader: five floats then an int, 24-byte stride.
private struct VisualizerUniforms {
    var time: Float
    var bass: Float
    var level: Float
    var aspect: Float
    var fade: Float
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
    float fade;
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

/// Painting black at low alpha is what leaves trails behind moving geometry.
fragment float4 f_fade(FS in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    return float4(0.0, 0.0, 0.0, u.fade);
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
        col = palette(v * 0.5 + t * 0.02, 0.0) * (0.35 + u.level * 1.1 + band * 0.9);
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
        col = palette(r * 1.4 + t * 0.05, 0.2) * (0.2 + band * 2.4) * (0.45 + 0.55 * pattern * rings);
        col *= smoothstep(1.05, 0.1, r);
    } else if (u.mode == 2) {
        // Aurora: drifting curtains whose height follows the spectrum.
        float y = 1.0 - uv.y;
        float band = bandAt(spectrum, uv.x);
        float n = fbm(float2(uv.x * 3.0, y * 1.6 - t * 0.22));
        float crest = 0.18 + n * 0.42 + band * 0.55;
        float glow = exp(-abs(y - crest) * 7.5);
        float veil = exp(-abs(y - crest * 0.6) * 3.0) * 0.35;
        col = palette(uv.x * 0.6 + t * 0.03, 0.35) * (glow + veil) * (0.8 + u.level * 2.0);
        col += float3(0.02, 0.05, 0.12) * (1.0 - y);
    } else if (u.mode == 3) {
        // Nebula: domain-warped noise, breathing on bass.
        float2 q = p * 2.2;
        float tt = t * 0.06;
        float warp = fbm(q * 0.8 - tt);
        float n = fbm(q * 1.5 + float2(tt, -tt) + warp * 1.2);
        float d = length(q);
        col = palette(n + u.bass * 0.3, 0.5) * pow(n, 2.0) * 2.6;
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
        col = palette(field * 0.22 + t * 0.03, 0.15) * m * (0.7 + u.level);
        col += palette(field * 0.22, 0.15) * edge * 0.5;
    } else {
        // Warp: a tunnel, with the throttle on bass.
        float r = max(0.02, length(p));
        float a = atan2(p.y, p.x);
        float z = 0.35 / r + t * 0.6 * (1.0 + u.bass * 0.8);
        float band = bandAt(spectrum, fract(z * 0.15));
        float stripes = 0.5 + 0.5 * sin(z * 6.0 + sin(a * 5.0 + t) * 1.2);
        col = palette(fract(z * 0.08), 0.6) * stripes * (0.25 + band * 2.2);
        col *= smoothstep(0.0, 0.22, r) * smoothstep(1.25, 0.28, r);
    }

    return float4(col, 1.0);
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

    private let commandQueue: MTLCommandQueue
    private let solidPipeline: MTLRenderPipelineState
    private let pointPipeline: MTLRenderPipelineState
    private let fadePipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let proceduralPipeline: MTLRenderPipelineState

    private var vertices: [VisualizerVertex] = []
    private var vertexBuffer: MTLBuffer?
    private var vertexCapacity = 0

    private var particles: [Particle] = []
    private var stars: [Particle] = []
    private var drops: [Particle] = []
    private var smoothedSpectrum = [Float](repeating: 0, count: 64)
    private var bassEnvelope: Float = 0
    private var lastBass: Float = 0
    private var phase: Float = 0

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let uniformBuffer: MTLBuffer
    private let spectrumBuffer: MTLBuffer

    /// Geometry accumulates here instead of straight into the drawable: the
    /// swap chain rotates through several drawables, so "last frame" only
    /// exists if we keep it ourselves. This is what makes trails possible.
    private var accumTexture: MTLTexture?
    private var accumNeedsClear = true

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vfn = library.makeFunction(name: "v_main"),
              let vfull = library.makeFunction(name: "v_full"),
              let solidFn = library.makeFunction(name: "f_solid"),
              let pointFn = library.makeFunction(name: "f_point"),
              let fadeFn = library.makeFunction(name: "f_fade"),
              let compFn = library.makeFunction(name: "f_composite"),
              let procFn = library.makeFunction(name: "f_procedural"),
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
              let fade = pipeline(vfull, fadeFn, blend: .alpha),
              let comp = pipeline(vfull, compFn, blend: .none),
              let proc = pipeline(vfull, procFn, blend: .none) else { return nil }

        solidPipeline = solid
        pointPipeline = point
        fadePipeline = fade
        compositePipeline = comp
        proceduralPipeline = proc
        super.init()
    }

    private enum BlendMode { case none, alpha, additive }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        accumTexture = nil
    }

    private func ensureAccum(size: CGSize) -> MTLTexture? {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        if let texture = accumTexture, texture.width == width, texture.height == height {
            return texture
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        accumTexture = device.makeTexture(descriptor: desc)
        accumNeedsClear = true
        return accumTexture
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let accum = ensureAccum(size: view.drawableSize),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let frame = frameProvider?() ?? VisualizerFrame(
            waveform: [Float](repeating: 0, count: 256),
            spectrum: [Float](repeating: 0, count: 64),
            bass: 0, level: 0
        )

        let aspect = Float(view.drawableSize.width / max(1, view.drawableSize.height))
        advance(frame: frame)
        uploadUniforms(aspect: aspect, frame: frame)

        // Pass 1 — everything lands in the accumulation texture.
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = accum
        scenePass.colorAttachments[0].loadAction = accumNeedsClear ? .clear : .load
        scenePass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        scenePass.colorAttachments[0].storeAction = .store
        accumNeedsClear = false

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePass) {
            if mode.isProcedural {
                encoder.setRenderPipelineState(proceduralPipeline)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(spectrumBuffer, offset: 0, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            } else {
                encoder.setRenderPipelineState(fadePipeline)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

                buildVertices(frame: frame, aspect: aspect)
                if !vertices.isEmpty, let buffer = ensureBuffer(count: vertices.count) {
                    buffer.contents().copyMemory(
                        from: vertices,
                        byteCount: vertices.count * MemoryLayout<VisualizerVertex>.stride
                    )
                    encoder.setRenderPipelineState(mode.isParticle ? pointPipeline : solidPipeline)
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                    encoder.drawPrimitives(
                        type: mode.isParticle ? .point : .triangle,
                        vertexStart: 0,
                        vertexCount: vertices.count
                    )
                }
            }
            encoder.endEncoding()
        }

        // Pass 2 — tone-map the accumulation onto the drawable.
        if let present = view.currentRenderPassDescriptor {
            present.colorAttachments[0].loadAction = .dontCare
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: present) {
                encoder.setRenderPipelineState(compositePipeline)
                encoder.setFragmentTexture(accum, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func uploadUniforms(aspect: Float, frame: VisualizerFrame) {
        var uniforms = VisualizerUniforms(
            time: phase * 4,
            bass: bassEnvelope,
            level: frame.level,
            aspect: aspect,
            fade: mode.trailFade,
            mode: mode.proceduralIndex ?? 0
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
        phase += 0.012

        // Attack fast, release slow: a kick should snap and then fall away.
        for i in smoothedSpectrum.indices where i < frame.spectrum.count {
            let target = frame.spectrum[i]
            let rate: Float = target > smoothedSpectrum[i] ? 0.55 : 0.12
            smoothedSpectrum[i] += (target - smoothedSpectrum[i]) * rate
        }

        bassEnvelope += (frame.bass - bassEnvelope) * (frame.bass > bassEnvelope ? 0.6 : 0.08)
        let rising = max(0, frame.bass - lastBass)
        lastBass = frame.bass

        // Only the active particle system keeps state.
        if mode != .bloom { particles.removeAll(keepingCapacity: true) }
        if mode != .starfield { stars.removeAll(keepingCapacity: true) }
        if mode != .matrix { drops.removeAll(keepingCapacity: true) }

        switch mode {
        case .bloom: advanceBloom(rising: rising)
        case .starfield: advanceStars(level: frame.level)
        case .matrix: advanceDrops()
        default: break
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
        let spawn = 3 + Int(level * 14)
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

    private func buildVertices(frame: VisualizerFrame, aspect: Float) {
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
        default: break
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
    let frameProvider: () -> VisualizerFrame

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
            renderer.frameProvider = frameProvider
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.mode = mode
        context.coordinator.renderer?.frameProvider = frameProvider
    }
}

// MARK: - Window contents

struct VisualizerWindow: View {
    @EnvironmentObject private var engine: AudioEngine
    @AppStorage(VisualizerMode.storageKey) private var storedMode = VisualizerMode.bars.rawValue
    @State private var showChrome = true
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
                MetalVisualizerView(mode: mode) { engine.visualizerFrame() }
                    .ignoresSafeArea()
            }

            if showChrome {
                HStack(spacing: 12) {
                    Picker("", selection: $storedMode) {
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
