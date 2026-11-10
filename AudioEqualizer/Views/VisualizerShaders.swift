// SPDX-License-Identifier: GPL-3.0-or-later

/// Every Metal function the visualizer uses, compiled at runtime from this
/// string so there is no `.metal` file to register in the project.
///
/// `Uniforms` here must stay in step with `VisualizerUniforms` in
/// `VisualizerView.swift`: twenty floats then an int, 84-byte stride.
///
/// Procedural modes are one function each, dispatched by `u.mode` in
/// `f_procedural`. They read three audio sources: the 64-bin spectrum
/// (`bandAt`), the 256-sample waveform (`waveAt`) and a 64x128 spectrum
/// history texture (`histAt`) whose newest row is at `u.histHead`. Every
/// time-based term reads `u.time`, which only advances with audio.
let visualizerShaderSource = """
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
    float mid;
    float treb;
    float beat;
    float fade;
    float seed;
    float histHead;
    float bloom;
    float pad;
    int mode;
};

struct FS { float4 position [[position]]; float2 uv; };

// --- Helpers ---

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static float2 hash22(float2 p) {
    float2 q = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return fract(sin(q) * 43758.5453123);
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

static float waveAt(const device float* wave, float x) {
    float f = clamp(x, 0.0, 0.9999) * 255.0;
    int i = int(f);
    return mix(wave[i], wave[min(i + 1, 255)], fract(f));
}

/// Spectrum `depth` (0 = now, 1 = oldest) rows back in the history ring.
static float histAt(texture2d<float> hist, float x, float depth, float head) {
    constexpr sampler hs(s_address::clamp_to_edge, t_address::repeat, filter::linear);
    return hist.sample(hs, float2(clamp(x, 0.004, 0.996), head - clamp(depth, 0.0, 1.0) * 0.96), level(0.0)).r;
}

static float2 rot2(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

/// Limits a trail's brightness by scaling the whole colour rather than each
/// channel, so a saturated trail stays its own hue instead of burning to white.
static float3 capped(float3 c) {
    float m = max(c.r, max(c.g, c.b));
    return c * min(1.0, 1.25 / max(m, 1e-4));
}

// --- CPU geometry ---

vertex VOut v_main(const device VIn* verts [[buffer(0)]], uint vid [[vertex_id]]) {
    VOut o;
    o.position = float4(verts[vid].pos, 0.0, 1.0);
    o.color = verts[vid].color;
    o.pointSize = verts[vid].size;
    return o;
}

fragment float4 f_solid(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    return float4(in.color.rgb, in.color.a * u.fade);
}

fragment float4 f_point(VOut in [[stage_in]], float2 pc [[point_coord]],
                        constant Uniforms& u [[buffer(0)]]) {
    float d = length(pc - float2(0.5, 0.5));
    // Two-lobe falloff: a tight core inside a wide halo reads as glow.
    float core = smoothstep(0.5, 0.0, d);
    float halo = smoothstep(0.5, 0.15, d);
    return float4(in.color.rgb, in.color.a * (core * 0.55 + halo * 0.75) * u.fade);
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

    // A beat nudges the zoom, so trails lurch outward on the kick.
    p /= max(0.01, u.zoom * (1.0 + u.beat * 0.012));

    // Ripple, scaled by bass so the warp breathes with the track.
    float w = u.warp * (0.6 + u.bass * 1.6);
    p += w * 0.02 * float2(sin(p.y * 7.0 + u.time * 1.3),
                           cos(p.x * 7.0 - u.time * 1.1));

    p += float2(u.dx, u.dy) * 0.01;

    p.x /= u.aspect;
    float2 uv = p + 0.5;

    // The accumulation buffer is floating point, so additive layers would
    // otherwise climb without limit under a slow decay; see `capped`.
    float3 col = capped(prev.sample(smp, uv).rgb) * u.decay;

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
    return float4(capped(prev.sample(smp, in.uv).rgb) * u.decay, 1.0);
}

/// Bloom from the accumulation texture's own mip chain, an exposure tone map
/// so bright cores roll off instead of clipping flat, a vignette, and a
/// static dither against banding in the long trails.
fragment float4 f_composite(FS in [[stage_in]],
                            constant Uniforms& u [[buffer(0)]],
                            texture2d<float> tex [[texture(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear, mip_filter::linear);
    float3 c = tex.sample(smp, in.uv, level(0.0)).rgb;
    float3 b = tex.sample(smp, in.uv, level(2.0)).rgb * 0.30
             + tex.sample(smp, in.uv, level(3.5)).rgb * 0.28
             + tex.sample(smp, in.uv, level(5.0)).rgb * 0.24
             + tex.sample(smp, in.uv, level(6.5)).rgb * 0.18;
    c += max(b - 0.16, float3(0.0)) * u.bloom;
    c = 1.0 - exp(-c * 1.9);
    float2 q = in.uv - 0.5;
    c *= 1.0 - dot(q, q) * 0.5;
    c += (hash21(in.position.xy) - 0.5) / 255.0;
    return float4(c, 1.0);
}

// --- Procedural modes ---

static float3 m_plasma(float2 p, float2 uv, Uniforms u, const device float* sp) {
    float t = u.time;
    float2 q = p * 3.0;
    float v = sin(q.x + t)
            + sin(q.y * 1.3 + t * 0.9)
            + sin((q.x + q.y) * 0.8 + t * 1.3)
            + sin(length(q) * 2.0 - t * 1.7 * (1.0 + u.bass));
    v *= 0.25;
    float band = bandAt(sp, uv.x);
    return palette(v * 0.5 + t * 0.02, u.paletteShift) * (0.35 + u.level * 1.1 + band * 0.9);
}

static float3 m_kaleidoscope(float2 p, Uniforms u, const device float* sp) {
    float t = u.time;
    float r = length(p);
    float a = atan2(p.y, p.x);
    float seg = 6.28318 / 10.0;
    a = abs(fmod(a + t * 0.15 + 100.0 * seg, seg) - seg * 0.5);
    float2 q = float2(cos(a), sin(a)) * r;
    float band = bandAt(sp, r * 1.7);
    float pattern = 0.5 + 0.5 * sin(q.x * 26.0 - t * 2.0 + band * 10.0);
    float rings = 0.5 + 0.5 * sin(r * 34.0 - t * 3.0);
    float3 col = palette(r * 1.4 + t * 0.05, 0.2 + u.paletteShift) * (0.2 + band * 2.4) * (0.45 + 0.55 * pattern * rings);
    return col * smoothstep(1.05, 0.1, r);
}

static float3 m_aurora(float2 uv, Uniforms u, const device float* sp) {
    float t = u.time;
    float y = 1.0 - uv.y;
    float band = bandAt(sp, uv.x);
    float n = fbm(float2(uv.x * 3.0, y * 1.6 - t * 0.22));
    float crest = 0.18 + n * 0.42 + band * 0.55;
    float glow = exp(-abs(y - crest) * 7.5);
    float veil = exp(-abs(y - crest * 0.6) * 3.0) * 0.35;
    float3 col = palette(uv.x * 0.6 + t * 0.03, 0.35 + u.paletteShift) * (glow + veil) * (0.8 + u.level * 2.0);
    return col + float3(0.02, 0.05, 0.12) * (1.0 - y);
}

static float3 m_nebula(float2 p, Uniforms u) {
    float2 q = p * 2.2;
    float tt = u.time * 0.06;
    float warp = fbm(q * 0.8 - tt);
    float n = fbm(q * 1.5 + float2(tt, -tt) + warp * 1.2);
    float d = length(q);
    float3 col = palette(n + u.bass * 0.3, 0.5 + u.paletteShift) * pow(n, 2.0) * 2.6;
    col *= smoothstep(1.7, 0.1, d);
    return col + palette(n, 0.5) * u.bass * 0.6 * exp(-d * 2.0);
}

static float3 m_metaballs(float2 p, Uniforms u, const device float* sp) {
    float t = u.time;
    float2 q = p * 2.0;
    float field = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float band = sp[int(fi * 9.0)];
        float ang = t * (0.3 + fi * 0.07) + fi * 1.7;
        float2 c = float2(cos(ang), sin(ang * 1.3)) * (0.3 + 0.4 * sin(t * 0.2 + fi));
        float rad = 0.10 + band * 0.38 + u.bass * 0.06;
        float2 delta = q - c;
        field += (rad * rad) / max(1e-4, dot(delta, delta));
    }
    float m = smoothstep(0.75, 1.7, field);
    float edge = smoothstep(1.7, 0.95, field);
    float3 col = palette(field * 0.22 + t * 0.03, 0.15 + u.paletteShift) * m * (0.7 + u.level);
    return col + palette(field * 0.22, 0.15) * edge * 0.5;
}

static float3 m_warp(float2 p, Uniforms u, const device float* sp) {
    float t = u.time;
    float r = max(0.02, length(p));
    float a = atan2(p.y, p.x);
    float z = 0.35 / r + t * 0.6 * (1.0 + u.bass * 0.8);
    float band = bandAt(sp, fract(z * 0.15));
    float stripes = 0.5 + 0.5 * sin(z * 6.0 + sin(a * 5.0 + t) * 1.2);
    float3 col = palette(fract(z * 0.08), 0.6 + u.paletteShift) * stripes * (0.25 + band * 2.2);
    return col * smoothstep(0.0, 0.22, r) * smoothstep(1.25, 0.28, r);
}

/// Julia set whose constant orbits with the clock, so the whole fractal
/// folds and unfolds as the track plays.
static float3 m_fractal(float2 p, Uniforms u, const device float* sp) {
    float t = u.time * 0.11 + u.seed * 6.0;
    float2 c = float2(-0.76 + 0.13 * cos(t * 1.3), 0.14 + 0.16 * sin(t)) + u.bass * float2(0.02, -0.015);
    float2 z = rot2(p, t * 0.2) * (2.5 - u.bass * 0.35);
    float m2 = 0.0;
    float n = 0.0;
    for (int i = 0; i < 56; i++) {
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        m2 = dot(z, z);
        if (m2 > 24.0) { break; }
        n += 1.0;
    }
    if (n >= 56.0) {
        return palette(m2 * 0.6 + t, u.paletteShift + 0.5) * 0.08 * (0.3 + u.level * 2.0);
    }
    float sm = (n - log2(max(1.0001, log2(max(1.0001, m2)))) + 4.0) / 56.0;
    float band = bandAt(sp, fract(sm * 3.0));
    float3 col = palette(sm * 3.2 + t * 0.4, u.paletteShift) * (0.22 + u.level * 1.3 + band * 1.3);
    // Fade the far field, where the escape time is short and the colour flat.
    return col * smoothstep(0.03, 0.30, sm);
}

/// Voronoi cells: each cell owns a random band and lights up with it.
static float3 m_cells(float2 p, Uniforms u, const device float* sp) {
    float2 q = p * 4.2;
    float2 g = floor(q);
    float d1 = 9.0;
    float d2 = 9.0;
    float2 nearest = float2(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 cell = g + float2(float(i), float(j));
            float2 o = hash22(cell + u.seed * 13.0);
            float2 pt = cell + 0.5 + 0.38 * sin(u.time * 0.6 + 6.2831 * o);
            float d = length(q - pt);
            if (d < d1) { d2 = d1; d1 = d; nearest = cell; }
            else if (d < d2) { d2 = d; }
        }
    }
    float edge = d2 - d1;
    float band = bandAt(sp, hash21(nearest + 3.7));
    float3 tint = palette(hash21(nearest + 7.0) * 0.5 + band * 0.3, u.paletteShift);
    float3 col = tint * (0.05 + band * 1.7) * (0.35 + 0.65 * smoothstep(0.0, 0.5, edge));
    col += tint * exp(-d1 * 9.0) * band * 1.4;
    col += palette(0.55, u.paletteShift) * smoothstep(0.07, 0.0, edge) * (0.12 + u.level * 1.3);
    return col;
}

/// A retro sunset: striped sun, spectrum mountains, and a grid that scrolls
/// toward the viewer at the speed of the music.
static float3 m_outrun(float2 p, float2 uv, Uniforms u, const device float* sp) {
    float y = 1.0 - uv.y;
    float h = 0.40;
    float3 col;
    if (y > h) {
        float sky = (y - h) / (1.0 - h);
        col = mix(float3(0.95, 0.25, 0.55), float3(0.07, 0.02, 0.20), pow(sky, 0.55));
        col *= 0.30 + u.level * 0.5;

        // Stars, twinkling on treble.
        float2 sg = floor(float2(p.x, y) * 90.0);
        float star = step(0.992, hash21(sg));
        col += star * sky * (0.15 + u.treb * 3.0);

        float2 sc = float2(p.x, y - h - 0.20);
        float sr = length(sc);
        float radius = 0.21 + u.bass * 0.025;
        if (sr < radius) {
            float sv = (sc.y + radius) / (2.0 * radius);
            float3 sun = mix(float3(1.0, 0.20, 0.55), float3(1.0, 0.92, 0.30), sv);
            float bars = step(0.42, fract(sv * 11.0 - u.time * 0.12));
            float cut = mix(bars, 1.0, smoothstep(0.30, 0.62, sv));
            col = sun * cut * (0.55 + u.level * 1.0 + u.beat * 0.25) + col * (1.0 - cut);
        }
        col += float3(1.0, 0.35, 0.55) * exp(-max(0.0, sr - radius) * 9.0) * (0.10 + u.bass * 0.55);

        // The spectrum as a mountain range, mirrored around the sun.
        float fx = clamp(abs(p.x) / (u.aspect * 0.5), 0.0, 1.0);
        float m = bandAt(sp, fx) * 0.30 * (0.35 + 0.65 * fx) + 0.012;
        float my = y - h;
        if (my < m) {
            col = mix(float3(0.03, 0.01, 0.10), float3(0.16, 0.04, 0.30), my / max(m, 1e-3));
        }
        col += float3(0.2, 0.9, 1.0) * smoothstep(0.007, 0.0, abs(my - m)) * (0.35 + u.level * 1.6);
    } else {
        float depth = h - y;
        float z = 0.16 / max(depth, 1e-3);
        float wx = p.x * z * 2.6;
        float wz = z * 1.4 + u.time * 0.9;
        float lw = 0.035 + 0.02 * z;
        float lx = smoothstep(lw, 0.0, abs(fract(wx) - 0.5));
        float lz = smoothstep(lw * 1.4, 0.0, abs(fract(wz) - 0.5));
        float grid = max(lx, lz) * smoothstep(0.0, 0.10, depth);
        col = float3(0.05, 0.01, 0.12) * (1.0 - depth);
        col += mix(float3(1.0, 0.25, 0.75), float3(0.2, 0.85, 1.0), clamp(depth * 2.2, 0.0, 1.0))
             * grid * (0.30 + u.level * 1.3 + u.beat * 0.5);
        col += float3(1.0, 0.3, 0.6) * exp(-depth * 26.0) * (0.25 + u.bass * 0.8);
    }
    return col;
}

/// Stacked ridgelines: each line is the spectrum a moment further back in
/// time, and nearer lines hide the ones behind.
static float3 m_ridgeline(float2 uv, Uniforms u, texture2d<float> hist) {
    float y = 1.0 - uv.y;
    float fx = abs(uv.x - 0.5) * 2.0;
    float env = pow(max(0.0, 1.0 - fx), 0.7);
    const int lines = 34;
    for (int k = 0; k < lines; k++) {
        float depth = float(k) / float(lines - 1);
        float base = 0.07 + depth * 0.62;
        float amp = histAt(hist, fx * 0.85, depth, u.histHead);
        float crest = base + amp * 0.26 * env * (1.0 - depth * 0.45);
        if (y < crest) {
            float line = smoothstep(0.0075, 0.0, crest - y);
            float3 tint = palette(depth * 0.55 + amp * 0.25, u.paletteShift);
            return tint * line * (1.15 - depth * 0.75) * (0.55 + amp * 1.4)
                 + tint * 0.045 * amp * (1.0 - depth);
        }
    }
    return float3(0.0);
}

/// A polar spectrogram: frequency runs around the circle, time runs outward.
static float3 m_chrono(float2 p, Uniforms u, texture2d<float> hist) {
    float r = length(p) * 2.0;
    float a = atan2(p.x, p.y);
    float fx = abs(a) / 3.14159265;
    float depth = clamp((r - 0.16) / 1.15, 0.0, 1.0);
    float v = histAt(hist, fx, depth, u.histHead);
    float3 col = palette(v * 0.6 + depth * 0.45, u.paletteShift) * pow(v, 1.5) * 2.4 * (1.0 - depth * 0.55);
    col *= smoothstep(0.14, 0.17, r);
    float ring = 0.5 + 0.5 * cos(depth * 60.0);
    col *= 0.82 + 0.18 * ring;
    col += palette(0.08, u.paletteShift) * exp(-r * r * 46.0) * (u.bass * 2.2);
    col += palette(0.3, u.paletteShift) * smoothstep(0.012, 0.0, abs(r - 0.155)) * (0.2 + u.level * 1.8);
    return col;
}

static float orbField(float3 q, Uniforms u, const device float* sp) {
    float r = length(q);
    float3 dir = q / max(r, 1e-4);
    float lat = acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265;
    float lon = atan2(dir.z, dir.x);
    float band = bandAt(sp, lat);
    float pattern = 0.5 + 0.5 * sin(lon * 9.0 + lat * 14.0 + u.time * 0.8);
    float disp = band * 0.46 * (0.15 + 0.85 * pattern * pattern) + u.bass * 0.07;
    return r - (0.85 + disp);
}

/// A raymarched sphere whose surface is pushed out by the spectrum:
/// bass at one pole, treble at the other.
static float3 m_orb(float2 p, Uniforms u, const device float* sp) {
    float3 ro = float3(0.0, 0.0, -3.1);
    float3 rd = normalize(float3(p * 1.25, 1.5));
    float ang = u.time * 0.22;
    float ca = cos(ang);
    float sa = sin(ang);
    float tilt = 0.45;
    float ct = cos(tilt);
    float st = sin(tilt);

    float t = 1.4;
    float nearest = 9.0;
    bool hit = false;
    float3 q = float3(0.0);
    for (int i = 0; i < 64; i++) {
        float3 pos = ro + rd * t;
        pos = float3(pos.x, pos.y * ct - pos.z * st, pos.y * st + pos.z * ct);
        q = float3(pos.x * ca - pos.z * sa, pos.y, pos.x * sa + pos.z * ca);
        float d = orbField(q, u, sp);
        nearest = min(nearest, d);
        if (d < 0.004) { hit = true; break; }
        t += d * 0.45;
        if (t > 5.2) { break; }
    }

    if (!hit) {
        return palette(0.55, u.paletteShift) * exp(-nearest * 5.5) * (0.10 + u.level * 1.5);
    }

    float2 e = float2(0.012, 0.0);
    float3 n = normalize(float3(
        orbField(q + e.xyy, u, sp) - orbField(q - e.xyy, u, sp),
        orbField(q + e.yxy, u, sp) - orbField(q - e.yxy, u, sp),
        orbField(q + e.yyx, u, sp) - orbField(q - e.yyx, u, sp)));
    float3 view = normalize(-q);
    float height = length(q) - 0.85;
    float lat = acos(clamp(q.y / max(length(q), 1e-4), -1.0, 1.0)) / 3.14159265;
    float diff = max(0.0, dot(n, normalize(float3(0.5, 0.7, -0.5))));
    float fres = pow(1.0 - max(0.0, dot(n, view)), 2.5);
    float3 base = palette(lat * 0.7 + height * 1.6, u.paletteShift);
    float spec = pow(max(0.0, dot(reflect(-normalize(float3(0.5, 0.7, -0.5)), n), view)), 24.0);
    float3 col = base * (0.04 + diff * 0.80) * (0.5 + u.level * 1.1);
    col += base * max(0.0, height) * 1.1;
    col += palette(lat * 0.7 + 0.35, u.paletteShift) * fres * (0.35 + u.level * 1.0);
    col += float3(1.0) * spec * 0.6;
    return col;
}

/// Light rays from the centre, each angle driven by its own band.
static float3 m_rays(float2 p, Uniforms u, const device float* sp) {
    float r = length(p) * 2.0;
    float a = atan2(p.y, p.x) + u.time * 0.07;
    float f = abs(fract(a / 6.28318 * 3.0) * 2.0 - 1.0);
    float band = bandAt(sp, f);
    float streak = 0.55 + 0.45 * sin(a * 46.0 + vnoise(float2(a * 7.0, 1.0)) * 9.0);
    float reach = exp(-r * max(0.5, 3.0 - band * 2.6));
    float3 col = palette(f * 0.55 + r * 0.25, u.paletteShift) * pow(band, 1.2) * reach * streak * 2.6;
    col += palette(0.05, u.paletteShift) * exp(-r * r * 26.0) * (u.bass * 2.4 + u.level * 0.6);
    return col;
}

/// A honeycomb: bass in the middle, treble at the edge, each hexagon swelling
/// with its band while a ripple runs outward.
static float3 m_hive(float2 p, Uniforms u, const device float* sp) {
    float2 q = p * 8.0;
    const float2 s = float2(1.0, 1.7320508);
    float2 ca = (floor(q / s) + 0.5) * s;
    float2 cb = (floor((q - s * 0.5) / s) + 0.5) * s + s * 0.5;
    float2 la = q - ca;
    float2 lb = q - cb;
    bool first = dot(la, la) < dot(lb, lb);
    float2 local = first ? la : lb;
    float2 centre = first ? ca : cb;
    float2 al = abs(local);
    float d = max(dot(al, s * 0.5), al.x);
    float rr = clamp(length(centre) / 8.0 * 1.7, 0.0, 1.0);
    float band = bandAt(sp, rr);
    float ripple = 0.5 + 0.5 * sin(rr * 13.0 - u.time * 2.2);
    float size = 0.05 + band * 0.44;
    float inner = smoothstep(size, size - 0.05, d);
    float3 tint = palette(rr * 0.75 + hash21(centre) * 0.08, u.paletteShift);
    float3 col = tint * inner * (0.12 + band * 1.9) * (0.55 + 0.45 * ripple);
    col += tint * smoothstep(0.44, 0.5, d) * (0.05 + u.level * 0.35 + u.beat * 0.2);
    return col;
}

/// Ink in water: noise warped through itself twice, with contour lines that
/// catch the light on the bands.
static float3 m_ink(float2 p, Uniforms u, const device float* sp) {
    float2 q = p * 1.7 + u.seed * 9.0;
    float t = u.time * 0.07;
    float2 a = float2(fbm(q + t), fbm(q + float2(5.2, 1.3) - t));
    float2 b = float2(fbm(q + 3.0 * a + float2(1.7, 9.2) + t * 0.7),
                      fbm(q + 3.0 * a + float2(8.3, 2.8) - t * 0.5));
    float f = fbm(q + 3.0 * b * (1.0 + u.bass * 0.45));
    float iso = smoothstep(0.18, 0.0, abs(sin(f * 20.0 + length(b) * 5.0)));
    float3 col = palette(f * 1.3 + length(a) * 0.6, u.paletteShift) * (f * f * 2.4 + 0.03) * (0.30 + u.level * 1.5);
    col += palette(f + 0.3, u.paletteShift) * iso * bandAt(sp, f) * 1.5;
    return col;
}

/// The waveform as three crossed laser lines.
static float3 m_laser(float2 p, Uniforms u, const device float* wave) {
    float3 col = float3(0.0);
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float2 q = rot2(p, fk * 1.0472 + u.time * 0.05);
        float x = q.x * 0.72 + 0.5;
        float window = sin(clamp(x, 0.0, 1.0) * 3.14159265);
        float y = waveAt(wave, x) * 0.42 * window;
        float d = abs(q.y - y);
        float glow = min(4.0, 0.0030 / (d + 0.0018));
        col += palette(fk * 0.33 + x * 0.25, u.paletteShift) * glow * window * (u.level * 2.4 + u.beat * 0.4);
    }
    return col;
}

/// A two-armed spiral galaxy: the arms brighten outward with the bands.
static float3 m_galaxy(float2 p, Uniforms u, const device float* sp) {
    float r = length(p) * 2.3;
    float a = atan2(p.y, p.x);
    float swirl = a + log(r + 0.06) * 3.2 - u.time * 0.22;
    float arm = pow(0.5 + 0.5 * cos(swirl * 2.0), 2.6);
    float band = bandAt(sp, clamp(r * 0.75, 0.0, 1.0));
    float dust = fbm(float2(swirl * 1.6, r * 5.5));
    float3 col = palette(r * 0.45 + dust * 0.25, u.paletteShift) * arm * exp(-r * 1.25)
               * (0.18 + band * 2.6) * (0.45 + dust * 1.1);
    float star = pow(hash21(floor(p * 240.0)), 60.0);
    col += star * (0.25 + arm) * (0.10 + u.treb * 3.5) * exp(-r * 0.7);
    col += palette(0.08, u.paletteShift) * exp(-r * r * 16.0) * (0.12 + u.bass * 2.4);
    return col;
}

/// Concentric rings, one band each, under a rotating radar sweep.
static float3 m_sonar(float2 p, Uniforms u, const device float* sp) {
    float r = length(p) * 2.1;
    float fr = r * 22.0;
    float idx = floor(fr);
    if (idx >= 24.0) { return float3(0.0); }
    float local = abs(fract(fr) - 0.5);
    float band = sp[int(min(63.0, idx * 2.7))];
    float w = 0.05 + band * 0.42;
    float ring = smoothstep(w, w - 0.05, local);
    float a = atan2(p.y, p.x) / 6.28318;
    float trail = pow(fract(a - u.time * 0.07), 4.0);
    float3 col = palette(idx / 24.0 * 0.8, u.paletteShift) * ring * (0.06 + band * 1.9) * (0.55 + 1.2 * trail);
    col += palette(0.5, u.paletteShift) * trail * trail * 0.10 * u.level * smoothstep(1.1, 0.0, r);
    return col;
}

/// Truchet arcs as circuit traces, with pulses running along the lit ones.
static float3 m_circuit(float2 p, Uniforms u, const device float* sp) {
    float2 q = p * 6.5 + u.seed * 17.0;
    float2 id = floor(q);
    float2 f = fract(q);
    if (hash21(id) > 0.5) { f.x = 1.0 - f.x; }
    float d = min(abs(length(f) - 0.5), abs(length(1.0 - f) - 0.5));
    float band = bandAt(sp, hash21(id + 3.1));
    float pulse = 0.5 + 0.5 * sin((f.x - f.y) * 6.28318 + u.time * 3.0 + hash21(id) * 6.28318);
    float line = smoothstep(0.075, 0.02, d);
    float glow = 0.014 / (d + 0.012);
    float3 tint = palette(hash21(id * 1.7) * 0.25 + length(p) * 0.5, u.paletteShift);
    return tint * (line * (0.07 + band * 1.9) + glow * band * pulse * 0.9);
}

static float skylineHeight(float2 cell, Uniforms u, texture2d<float> hist) {
    if (cell.y < 0.0 || cell.y > 43.0 || abs(cell.x + 0.5) > 18.0) { return 0.0; }
    float fx = abs(cell.x + 0.5) / 18.0;
    return 0.04 + histAt(hist, fx, cell.y / 44.0, u.histHead) * 2.3;
}

/// A city of spectrum bars, raymarched: the front row is now, and each row
/// behind it is a moment earlier.
static float3 m_skyline(float2 p, Uniforms u, texture2d<float> hist) {
    const float cs = 0.5;
    float3 ro = float3(0.0, 2.7, -2.4);
    float3 fwd = normalize(float3(0.0, -0.36, 1.0));
    float3 right = float3(1.0, 0.0, 0.0);
    float3 up = cross(fwd, right);
    float3 rd = normalize(fwd * 1.35 + right * p.x - up * p.y);

    float3 sky = mix(float3(0.01, 0.01, 0.04), palette(0.62, u.paletteShift) * 0.22,
                     smoothstep(-0.25, 0.5, p.y)) * (0.4 + u.level);
    if (rd.y >= -0.01) { return sky; }

    float t = 0.0;
    float3 col = sky;
    for (int i = 0; i < 96; i++) {
        float3 pos = ro + rd * t;
        if (pos.y < 0.0) {
            // The floor picks up a faint glow from the bars above it.
            float2 g = abs(fract(pos.xz / cs) - 0.5);
            float lines = smoothstep(0.47, 0.5, max(g.x, g.y));
            col = palette(0.6, u.paletteShift) * lines * 0.16 * (0.3 + u.level * 2.0);
            col = mix(sky, col, exp(-t * 0.055));
            break;
        }
        if (t > 30.0) { break; }

        float2 cell = floor(pos.xz / cs);
        float h = skylineHeight(cell, u, hist);
        float2 local = pos.xz - (cell + 0.5) * cs;
        float3 b = float3(0.19, h * 0.5, 0.19);
        float3 qq = abs(float3(local.x, pos.y - h * 0.5, local.y)) - b;
        float d = length(max(qq, float3(0.0))) + min(max(qq.x, max(qq.y, qq.z)), 0.0);

        if (d < 0.004 && h > 0.0) {
            float fx = abs(cell.x + 0.5) / 18.0;
            float3 tint = palette(fx * 0.7 + cell.y * 0.012, u.paletteShift);
            bool top = qq.y > max(qq.x, qq.z);
            float shade = top ? 1.25 : (qq.x > qq.z ? 0.42 : 0.72);
            float rise = clamp(pos.y / max(h, 0.05), 0.0, 1.0);
            col = tint * shade * (0.10 + 0.90 * rise * rise) * (0.55 + h * 0.5);
            col += tint * smoothstep(0.06, 0.0, h - pos.y) * 0.9;
            col = mix(sky, col, exp(-t * 0.055));
            break;
        }

        // Never step past the edge of this cell: its neighbour may be taller.
        float tx = rd.x > 0.0 ? (cs * 0.5 - local.x) / max(rd.x, 1e-4) : (-cs * 0.5 - local.x) / min(rd.x, -1e-4);
        float tz = rd.z > 0.0 ? (cs * 0.5 - local.y) / max(rd.z, 1e-4) : (-cs * 0.5 - local.y) / min(rd.z, -1e-4);
        t += max(0.004, min(d, min(tx, tz) + 0.004));
    }
    return col;
}

/// A total eclipse: the corona reaches further where its band is louder.
static float3 m_eclipse(float2 p, Uniforms u, const device float* sp) {
    float r = length(p) * 2.0;
    float a = atan2(p.x, p.y);
    float f = abs(a) / 3.14159265;
    float band = bandAt(sp, f);
    float n = fbm(float2(a * 3.0, r * 2.2 - u.time * 0.35));
    float radius = 0.44 + u.bass * 0.035;
    float outside = step(radius, r);
    float falloff = max(0.7, 5.5 - band * 3.6 - n * 1.6);
    float corona = exp(-(r - radius) * falloff) * outside;
    float3 col = palette(0.06 + band * 0.22 + (r - radius) * 0.25, u.paletteShift)
               * corona * (0.10 + band * 2.2 + u.level * 0.9) * (0.6 + n * 0.8);
    col += float3(1.0, 0.92, 0.82) * exp(-abs(r - radius) * 70.0) * (u.level * 2.0 + u.beat * 0.5);
    return col;
}

/// Twelve strings, pinned at both ends, each plucked by its own band.
static float3 m_strings(float2 p, Uniforms u, const device float* sp) {
    float3 col = float3(0.0);
    float x = clamp(p.x / u.aspect + 0.5, 0.0, 1.0);
    float pin = sin(x * 3.14159265);
    for (int k = 0; k < 12; k++) {
        float fk = float(k) / 11.0;
        float band = sp[k * 5 + 2];
        float rest = (fk - 0.5) * 0.82;
        float y = rest + band * 0.085 * pin * sin(x * (5.0 + float(k) * 2.2) * 3.14159265 + u.time * (2.0 + fk * 4.0));
        float d = abs(p.y - y);
        col += palette(fk * 0.8, u.paletteShift) * min(3.0, 0.0014 / (d + 0.0016)) * (0.02 + band * 1.5);
    }
    return col;
}

fragment float4 f_procedural(FS in [[stage_in]],
                             constant Uniforms& u [[buffer(0)]],
                             const device float* spectrum [[buffer(1)]],
                             const device float* wave [[buffer(2)]],
                             texture2d<float> hist [[texture(0)]]) {
    float2 uv = in.uv;
    float2 p = (uv - 0.5) * float2(u.aspect, 1.0);
    float3 col;

    switch (u.mode) {
        case 0: col = m_plasma(p, uv, u, spectrum); break;
        case 1: col = m_kaleidoscope(p, u, spectrum); break;
        case 2: col = m_aurora(uv, u, spectrum); break;
        case 3: col = m_nebula(p, u); break;
        case 4: col = m_metaballs(p, u, spectrum); break;
        case 5: col = m_warp(p, u, spectrum); break;
        case 6: col = m_fractal(p, u, spectrum); break;
        case 7: col = m_cells(p, u, spectrum); break;
        case 8: col = m_outrun(p, uv, u, spectrum); break;
        case 9: col = m_ridgeline(uv, u, hist); break;
        case 10: col = m_chrono(p, u, hist); break;
        case 11: col = m_orb(p, u, spectrum); break;
        case 12: col = m_rays(p, u, spectrum); break;
        case 13: col = m_hive(p, u, spectrum); break;
        case 14: col = m_ink(p, u, spectrum); break;
        case 15: col = m_laser(p, u, wave); break;
        case 16: col = m_galaxy(p, u, spectrum); break;
        case 17: col = m_sonar(p, u, spectrum); break;
        case 18: col = m_circuit(p, u, spectrum); break;
        case 19: col = m_skyline(p, u, hist); break;
        case 20: col = m_eclipse(p, u, spectrum); break;
        default: col = m_strings(p, u, spectrum); break;
    }

    return float4(max(col, float3(0.0)), u.overlayAlpha * u.fade);
}
"""
