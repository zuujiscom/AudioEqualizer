// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// A reader for MilkDrop `.milk` presets.
//
// Only the motion half of a preset is used: the `per_frame_N` equations and the
// static header values they start from. Those drive the feedback transform this
// app already has — zoom, rotation, drift, stretch, warp and decay. The
// `per_pixel` mesh warp, custom waves and shapes, and MilkDrop 2's HLSL shader
// blocks are all ignored, so an imported preset is a faithful rendering of its
// *motion*, not a pixel-accurate reproduction.
//
// Importing the static values alone would not be worth doing: across the
// original preset pack, rot/dx/dy/cx/cy/sx/sy sit at their defaults and all the
// movement lives in the equations.

// MARK: - Expression evaluation

/// MilkDrop's per-frame language: assignments separated by `;`, infix
/// arithmetic, and a small set of functions. Parsed once at load into a tree,
/// then evaluated every frame.
indirect enum MilkdropNode {
    case constant(Double)
    case variable(String)
    case unaryMinus(MilkdropNode)
    case binary(String, MilkdropNode, MilkdropNode)
    case call(String, [MilkdropNode])
}

struct MilkdropStatement {
    let target: String
    let value: MilkdropNode
}

enum MilkdropParser {
    private struct Cursor {
        let text: [Character]
        var index = 0
        init(_ s: String) { text = Array(s) }

        mutating func skipSpace() {
            while index < text.count, text[index] == " " || text[index] == "\t" { index += 1 }
        }
        var current: Character? { index < text.count ? text[index] : nil }
        mutating func match(_ c: Character) -> Bool {
            skipSpace()
            guard current == c else { return false }
            index += 1
            return true
        }
    }

    /// Splits a program into statements and parses each right-hand side.
    static func parse(program: String) -> [MilkdropStatement] {
        var statements: [MilkdropStatement] = []
        for raw in program.split(separator: ";") {
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty, let eq = piece.firstIndex(of: "=") else { continue }
            let target = piece[piece.startIndex..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            guard !target.isEmpty, target.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            var cursor = Cursor(String(piece[piece.index(after: eq)...]))
            guard let node = parseExpression(&cursor) else { continue }
            statements.append(MilkdropStatement(target: target, value: node))
        }
        return statements
    }

    private static func parseExpression(_ c: inout Cursor) -> MilkdropNode? {
        guard var left = parseTerm(&c) else { return nil }
        while true {
            c.skipSpace()
            guard let op = c.current, op == "+" || op == "-" else { return left }
            c.index += 1
            guard let right = parseTerm(&c) else { return left }
            left = .binary(String(op), left, right)
        }
    }

    private static func parseTerm(_ c: inout Cursor) -> MilkdropNode? {
        guard var left = parseFactor(&c) else { return nil }
        while true {
            c.skipSpace()
            guard let op = c.current, op == "*" || op == "/" || op == "%" else { return left }
            c.index += 1
            guard let right = parseFactor(&c) else { return left }
            left = .binary(String(op), left, right)
        }
    }

    private static func parseFactor(_ c: inout Cursor) -> MilkdropNode? {
        c.skipSpace()
        if c.match("-") {
            guard let inner = parseFactor(&c) else { return nil }
            return .unaryMinus(inner)
        }
        if c.match("+") { return parseFactor(&c) }
        guard let node = parseAtom(&c) else { return nil }
        c.skipSpace()
        if c.match("^") {
            guard let exponent = parseFactor(&c) else { return node }
            return .call("pow", [node, exponent])
        }
        return node
    }

    private static func parseAtom(_ c: inout Cursor) -> MilkdropNode? {
        c.skipSpace()
        guard let ch = c.current else { return nil }

        if c.match("(") {
            let inner = parseExpression(&c)
            _ = c.match(")")
            return inner
        }

        if ch.isNumber || ch == "." {
            var text = ""
            while let d = c.current, d.isNumber || d == "." { text.append(d); c.index += 1 }
            // Exponent form, e.g. 1e-3
            if let e = c.current, e == "e" || e == "E" {
                var lookahead = c
                lookahead.index += 1
                var expText = "e"
                if let sign = lookahead.current, sign == "+" || sign == "-" {
                    expText.append(sign); lookahead.index += 1
                }
                if let d = lookahead.current, d.isNumber {
                    while let d = lookahead.current, d.isNumber { expText.append(d); lookahead.index += 1 }
                    text += expText
                    c = lookahead
                }
            }
            return .constant(Double(text) ?? 0)
        }

        if ch.isLetter || ch == "_" {
            var name = ""
            while let d = c.current, d.isLetter || d.isNumber || d == "_" { name.append(d); c.index += 1 }
            name = name.lowercased()
            c.skipSpace()
            if c.match("(") {
                var args: [MilkdropNode] = []
                if !c.match(")") {
                    while true {
                        guard let arg = parseExpression(&c) else { break }
                        args.append(arg)
                        if c.match(",") { continue }
                        _ = c.match(")")
                        break
                    }
                }
                return .call(name, args)
            }
            return .variable(name)
        }

        c.index += 1
        return nil
    }
}

enum MilkdropEvaluator {
    static func evaluate(_ node: MilkdropNode, vars: [String: Double]) -> Double {
        switch node {
        case .constant(let v):
            return v
        case .variable(let name):
            return vars[name] ?? 0
        case .unaryMinus(let inner):
            return -evaluate(inner, vars: vars)
        case .binary(let op, let l, let r):
            let a = evaluate(l, vars: vars)
            let b = evaluate(r, vars: vars)
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/": return b == 0 ? 0 : a / b
            case "%": return b == 0 ? 0 : a.truncatingRemainder(dividingBy: b)
            default: return 0
            }
        case .call(let name, let args):
            func arg(_ i: Int) -> Double { i < args.count ? evaluate(args[i], vars: vars) : 0 }
            switch name {
            case "sin": return sin(arg(0))
            case "cos": return cos(arg(0))
            case "tan": return tan(arg(0))
            case "asin": return asin(max(-1, min(1, arg(0))))
            case "acos": return acos(max(-1, min(1, arg(0))))
            case "atan": return atan(arg(0))
            case "atan2": return atan2(arg(0), arg(1))
            case "abs": return abs(arg(0))
            case "sqr": return arg(0) * arg(0)
            case "sqrt": return sqrt(max(0, arg(0)))
            case "pow": return pow(arg(0), arg(1))
            case "exp": return exp(arg(0))
            case "log": return arg(0) > 0 ? log(arg(0)) : 0
            case "log10": return arg(0) > 0 ? log10(arg(0)) : 0
            case "int", "floor": return floor(arg(0))
            case "ceil": return ceil(arg(0))
            case "frac": return arg(0) - floor(arg(0))
            case "sign": return arg(0) > 0 ? 1 : (arg(0) < 0 ? -1 : 0)
            case "min": return Swift.min(arg(0), arg(1))
            case "max": return Swift.max(arg(0), arg(1))
            case "above": return arg(0) > arg(1) ? 1 : 0
            case "below": return arg(0) < arg(1) ? 1 : 0
            case "equal": return arg(0) == arg(1) ? 1 : 0
            case "if": return arg(0) != 0 ? arg(1) : arg(2)
            case "band": return (arg(0) != 0 && arg(1) != 0) ? 1 : 0
            case "bor": return (arg(0) != 0 || arg(1) != 0) ? 1 : 0
            case "bnot": return arg(0) == 0 ? 1 : 0
            case "sigmoid": return 1 / (1 + exp(-arg(0) * arg(1)))
            case "rand": return Double.random(in: 0..<Swift.max(1, arg(0)))
            default: return 0
            }
        }
    }
}

// MARK: - Preset

/// The motion a preset asks for on a given frame.
struct MilkdropMotion {
    var zoom: Double = 1
    var rot: Double = 0
    var warp: Double = 1
    var dx: Double = 0
    var dy: Double = 0
    var cx: Double = 0.5
    var cy: Double = 0.5
    var sx: Double = 1
    var sy: Double = 1
    var decay: Double = 0.98
}

/// Audio levels in MilkDrop's terms, where 1.0 is "average loudness" for that
/// band rather than an absolute level. Presets lean on that normalisation
/// heavily — `sin(bass_att)` only behaves if bass_att hovers around 1.
struct MilkdropAudio {
    var bass: Double = 1
    var mid: Double = 1
    var treb: Double = 1
    var bassAtt: Double = 1
    var midAtt: Double = 1
    var trebAtt: Double = 1
    var vol: Double = 1
    var volAtt: Double = 1
}

final class MilkdropPreset {
    let name: String
    let rating: Double
    private let initialVars: [String: Double]
    private let initStatements: [MilkdropStatement]
    private let frameStatements: [MilkdropStatement]
    private let pixelStatements: [MilkdropStatement]

    /// Persists across frames: MilkDrop guarantees user variables keep their
    /// values from one frame to the next, and presets rely on it to integrate.
    private var state: [String: Double] = [:]
    private var frameVars: [String: Double] = [:]
    private var frameCount: Double = 0

    var hasPixelEquations: Bool { !pixelStatements.isEmpty }

    /// Header keys that seed the variable pool and provide fallbacks.
    private static let motionKeys = [
        "zoom", "rot", "warp", "dx", "dy", "cx", "cy", "sx", "sy", "decay"
    ]

    init?(contentsOf url: URL) {
        guard let raw = try? String(contentsOf: url, encoding: .isoLatin1) else { return nil }
        name = url.deletingPathExtension().lastPathComponent

        var header: [String: Double] = [:]
        var initLines: [(Int, String)] = []
        var frameLines: [(Int, String)] = []
        var pixelLines: [(Int, String)] = []

        for line in raw.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let eq = text.firstIndex(of: "=") else { continue }
            let key = String(text[text.startIndex..<eq])
            let value = String(text[text.index(after: eq)...])

            if key.hasPrefix("per_frame_init_") {
                initLines.append((Int(key.dropFirst("per_frame_init_".count)) ?? 0, value))
            } else if key.hasPrefix("per_frame_") {
                frameLines.append((Int(key.dropFirst("per_frame_".count)) ?? 0, value))
            } else if key.hasPrefix("per_pixel_") {
                pixelLines.append((Int(key.dropFirst("per_pixel_".count)) ?? 0, value))
            } else if let number = Double(value) {
                header[key] = number
            }
        }

        rating = header["fRating"] ?? 0

        // Seed from the header. MilkDrop's names differ from its variable names.
        var seed: [String: Double] = [:]
        seed["zoom"] = header["zoom"] ?? 1
        seed["rot"] = header["rot"] ?? 0
        seed["dx"] = header["dx"] ?? 0
        seed["dy"] = header["dy"] ?? 0
        seed["cx"] = header["cx"] ?? 0.5
        seed["cy"] = header["cy"] ?? 0.5
        seed["sx"] = header["sx"] ?? 1
        seed["sy"] = header["sy"] ?? 1
        seed["warp"] = header["fWarpScale"] ?? 1
        seed["decay"] = header["fDecay"] ?? 0.98
        seed["zoomexp"] = header["fZoomExponent"] ?? 1
        seed["wave_mode"] = header["nWaveMode"] ?? 0
        initialVars = seed

        initStatements = MilkdropParser.parse(program: initLines.sorted { $0.0 < $1.0 }
            .map(\.1).joined(separator: ";"))
        frameStatements = MilkdropParser.parse(program: frameLines.sorted { $0.0 < $1.0 }
            .map(\.1).joined(separator: ";"))
        pixelStatements = MilkdropParser.parse(program: pixelLines.sorted { $0.0 < $1.0 }
            .map(\.1).joined(separator: ";"))

        // A preset with no equations is just its header, which across the
        // original pack is entirely defaults — nothing worth importing.
        guard !frameStatements.isEmpty || !pixelStatements.isEmpty else { return nil }
        reset()
    }

    var waveMode: Int { Int(initialVars["wave_mode"] ?? 0) }

    /// Evaluates the per-pixel equations at one mesh vertex. `x`/`y` are 0...1
    /// across the screen, as MilkDrop supplies them, with `rad` and `ang`
    /// derived the same way. This is the half that makes an imported preset
    /// look like itself: the motion varies across the frame, which a single
    /// global transform cannot express.
    func stepPixel(x: Double, y: Double) -> MilkdropMotion {
        guard !pixelStatements.isEmpty else {
            return motion(from: frameVars)
        }
        var vars = frameVars
        let dx = x - 0.5
        let dy = y - 0.5
        vars["x"] = x
        vars["y"] = y
        vars["rad"] = sqrt(dx * dx + dy * dy) * 2
        vars["ang"] = atan2(dy, dx)
        for statement in pixelStatements {
            vars[statement.target] = MilkdropEvaluator.evaluate(statement.value, vars: vars)
        }
        return motion(from: vars)
    }

    private func motion(from vars: [String: Double]) -> MilkdropMotion {
        func value(_ key: String, _ fallback: Double) -> Double {
            let v = vars[key] ?? fallback
            return v.isFinite ? v : fallback
        }
        return MilkdropMotion(
            zoom: value("zoom", 1), rot: value("rot", 0), warp: value("warp", 1),
            dx: value("dx", 0), dy: value("dy", 0),
            cx: value("cx", 0.5), cy: value("cy", 0.5),
            sx: value("sx", 1), sy: value("sy", 1),
            decay: value("decay", 0.98)
        )
    }

    func reset() {
        state = initialVars
        frameCount = 0
        var vars = state
        for statement in initStatements {
            vars[statement.target] = MilkdropEvaluator.evaluate(statement.value, vars: vars)
        }
        state = vars
    }

    /// Runs the preset's per-frame equations once and returns the motion they ask for.
    func step(time: Double, fps: Double, audio: MilkdropAudio) -> MilkdropMotion {
        frameCount += 1

        // MilkDrop resets the built-in motion variables to their base values
        // every frame; only user variables (and q1-q32) carry over. Without
        // this, `zoom = zoom - 0.05` compounds instead of offsetting, and the
        // preset winds itself into nonsense within seconds.
        var vars = state
        for key in Self.motionKeys {
            vars[key] = initialVars[key] ?? vars[key] ?? 0
        }
        vars["time"] = time
        vars["frame"] = frameCount
        vars["fps"] = fps
        vars["bass"] = audio.bass
        vars["mid"] = audio.mid
        vars["treb"] = audio.treb
        vars["bass_att"] = audio.bassAtt
        vars["mid_att"] = audio.midAtt
        vars["treb_att"] = audio.trebAtt
        vars["vol"] = audio.vol
        vars["vol_att"] = audio.volAtt

        for statement in frameStatements {
            vars[statement.target] = MilkdropEvaluator.evaluate(statement.value, vars: vars)
        }
        state = vars
        frameVars = vars

        return motion(from: vars)
    }
}
