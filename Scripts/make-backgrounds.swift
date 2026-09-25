import AppKit

// Paints the generated wallpapers: flat gouache-style grounds with one simple, playful subject each.
// Every image is seeded, so re-running produces identical files.
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { print("usage: make-backgrounds output-folder [name-filter]"); exit(1) }
let output = URL(fileURLWithPath: arguments[1])
let filter = arguments.count > 2 ? arguments[2] : nil
let W = 1672.0, H = 941.0

// MARK: - Colour and randomness

struct Col {
    var r, g, b: Double
    init(_ hex: String) {
        let v = UInt32(hex.dropFirst(hex.hasPrefix("#") ? 1 : 0), radix: 16)!
        r = Double(v >> 16 & 255) / 255; g = Double(v >> 8 & 255) / 255; b = Double(v & 255) / 255
    }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    func mix(_ o: Col, _ t: Double) -> Col { Col(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    func light(_ t: Double) -> Col { mix(Col(r: 1, g: 0.98, b: 0.94), t) }
    func dark(_ t: Double) -> Col { mix(Col(r: 0.05, g: 0.04, b: 0.06), t) }
    func cg(_ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

struct RNG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
    mutating func range(_ r: ClosedRange<Double>) -> Double { r.lowerBound + next() * (r.upperBound - r.lowerBound) }
    mutating func sign() -> Double { next() < 0.5 ? -1 : 1 }
}

// MARK: - Geometry

func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// A closed Catmull-Rom curve through the points.
func smooth(_ pts: [CGPoint]) -> CGPath {
    let path = CGMutablePath(), n = pts.count
    path.move(to: pts[0])
    for i in 0..<n {
        let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
        path.addCurve(to: p2, control1: P(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6),
                      control2: P(p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6))
    }
    path.closeSubpath()
    return path
}

/// An open curve through the points, for stems, tails and necks.
func curve(_ pts: [CGPoint]) -> CGPath {
    let path = CGMutablePath(), n = pts.count
    path.move(to: pts[0])
    for i in 0..<(n - 1) {
        let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(n - 1, i + 2)]
        path.addCurve(to: p2, control1: P(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6),
                      control2: P(p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6))
    }
    return path
}

func place(_ pts: [(Double, Double)], at c: CGPoint, scale s: Double = 1, angle a: Double = 0, flip: Bool = false) -> [CGPoint] {
    pts.map { x0, y0 in
        let x = (flip ? -x0 : x0) * s, y = y0 * s
        return P(c.x + x * cos(a) - y * sin(a), c.y + x * sin(a) + y * cos(a))
    }
}

func polygon(_ pts: [CGPoint]) -> CGPath {
    let path = CGMutablePath(); path.addLines(between: pts); path.closeSubpath(); return path
}

func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGPath { CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil) }

// MARK: - Painter

final class Painter {
    let ctx: CGContext
    var rng: RNG
    init(seed: UInt64) {
        rng = RNG(seed)
        ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
    }

    /// A slightly irregular ellipse, like a shape cut from painted paper.
    func blob(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, wobble: Double = 0.025, angle: Double = 0) -> CGPath {
        let phases = (0..<4).map { _ in rng.range(0...(2 * .pi)) }
        let pts = (0..<40).map { i -> CGPoint in
            let t = Double(i) / 40 * 2 * .pi
            let k = 1 + wobble * (sin(2 * t + phases[0]) + 0.6 * sin(3 * t + phases[1]) + 0.35 * sin(5 * t + phases[2]) + 0.2 * sin(7 * t + phases[3])) / 2.15
            let x = cos(t) * rx * k, y = sin(t) * ry * k
            return P(cx + x * cos(angle) - y * sin(angle), cy + x * sin(angle) + y * cos(angle))
        }
        return smooth(pts)
    }

    /// Short translucent brush strokes of nearby tones, which read as gouache or acrylic texture.
    func strokes(in box: CGRect, _ base: Col, count: Int, length: ClosedRange<Double>, width: ClosedRange<Double>,
                 angle: Double, spread: Double = 0.35, jitter: Double = 0.08, alpha: ClosedRange<Double> = 0.06...0.16) {
        for _ in 0..<count {
            let x = rng.range(Double(box.minX)...Double(box.maxX)), y = rng.range(Double(box.minY)...Double(box.maxY))
            let a = angle + rng.range(-spread...spread), l = rng.range(length)
            let tone = rng.next() < 0.5 ? base.light(rng.range(0...jitter)) : base.dark(rng.range(0...jitter))
            ctx.setStrokeColor(tone.cg(rng.range(alpha)))
            ctx.setLineWidth(rng.range(width))
            let bend = rng.range(-0.25...0.25) * l
            ctx.move(to: P(x - cos(a) * l / 2, y - sin(a) * l / 2))
            ctx.addQuadCurve(to: P(x + cos(a) * l / 2, y + sin(a) * l / 2), control: P(x - sin(a) * bend, y + cos(a) * bend))
            ctx.strokePath()
        }
    }

    func background(_ c: Col, angle: Double? = nil) {
        ctx.setFillColor(c.cg()); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        mottle(CGRect(x: 0, y: 0, width: W, height: H), c, count: 50)
        let a = angle ?? rng.range(-0.6...0.6), all = CGRect(x: -60, y: -60, width: W + 120, height: H + 120)
        strokes(in: all, c, count: 3200, length: 60...220, width: 14...46, angle: a, spread: 0.3, jitter: 0.13, alpha: 0.07...0.2)
        strokes(in: all, c, count: 1800, length: 20...80, width: 4...12, angle: a + 0.4, spread: 1.2, jitter: 0.16, alpha: 0.06...0.16)
    }

    /// Large, soft tonal patches, as paint rarely dries perfectly even.
    func mottle(_ box: CGRect, _ c: Col, count: Int, strength: Double = 0.1) {
        for _ in 0..<count {
            let x = rng.range(Double(box.minX)...Double(box.maxX)), y = rng.range(Double(box.minY)...Double(box.maxY))
            let tone = rng.next() < 0.5 ? c.light(0.3) : c.dark(0.3), r = rng.range(0.15...0.45) * Double(max(box.width, box.height))
            let g = CGGradient(colorsSpace: nil, colors: [tone.cg(rng.range(0.3...1) * strength), tone.cg(0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: P(x, y), startRadius: 0, endCenter: P(x, y), endRadius: r, options: [])
        }
    }

    /// Fills a region with texture, then darkens the side away from the light and adds a soft highlight.
    func shape(_ path: CGPath, _ c: Col, light: CGPoint? = P(-0.45, -0.55), shade: Double = 0.38, shine: Double = 0.4,
               texture: Double = 1, strokeAngle: Double? = nil, edge: Double = 0.22) {
        let box = path.boundingBoxOfPath
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.setFillColor(c.cg()); ctx.fill(box)
        let area = Double(box.width * box.height), small = Double(min(box.width, box.height))
        mottle(box, c, count: 6, strength: 0.12 * texture)
        strokes(in: box.insetBy(dx: -20, dy: -20), c, count: Int(area / 380 * texture) + 16,
                length: max(10, small * 0.1)...max(24, small * 0.38), width: 4...max(7, small * 0.09),
                angle: strokeAngle ?? rng.range(-1...1), spread: 0.9, jitter: 0.16, alpha: 0.08...0.24)
        if let light {
            // Shade and highlight with strokes that follow the form, rather than an airbrushed gradient.
            let length = max(1e-6, hypot(Double(light.x), Double(light.y)))
            let dx = -Double(light.x) / length, dy = -Double(light.y) / length, across = atan2(dy, dx) + .pi / 2
            for _ in 0..<(Int(area / 260) + 20) {
                let x = rng.range(Double(box.minX)...Double(box.maxX)), y = rng.range(Double(box.minY)...Double(box.maxY))
                let t = ((x - Double(box.midX)) / Double(box.width) * dx + (y - Double(box.midY)) / Double(box.height) * dy) * 2
                let l = rng.range(small * 0.08...small * 0.3), a = across + rng.range(-0.35...0.35)
                if t > 0.05 { ctx.setStrokeColor(c.dark(rng.range(0.35...0.6)).cg(min(0.5, t * shade * 0.9) * rng.range(0.4...1))) }
                else if t < -0.25 && shine > 0 { ctx.setStrokeColor(c.light(rng.range(0.25...0.55)).cg(min(0.4, -t * shine * 0.45) * rng.range(0.3...1))) }
                else { continue }
                ctx.setLineWidth(rng.range(3...max(5, small * 0.06)))
                ctx.move(to: P(x - cos(a) * l / 2, y - sin(a) * l / 2))
                ctx.addQuadCurve(to: P(x + cos(a) * l / 2, y + sin(a) * l / 2), control: P(x + dx * l * 0.15, y + dy * l * 0.15))
                ctx.strokePath()
            }
            let lx = Double(box.midX) + Double(light.x) * Double(box.width), ly = Double(box.midY) + Double(light.y) * Double(box.height)
            let far = P(Double(box.midX) - Double(light.x) * Double(box.width) * 0.9, Double(box.midY) - Double(light.y) * Double(box.height) * 0.9)
            let radius = Double(max(box.width, box.height))
            let dark = CGGradient(colorsSpace: nil, colors: [c.dark(0.5).cg(shade * 0.55), c.dark(0.5).cg(0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(dark, startCenter: far, startRadius: 0, endCenter: far, endRadius: radius * 0.85, options: [])
            if shine > 0 {
                let glow = CGGradient(colorsSpace: nil, colors: [c.light(0.75).cg(shine * 0.5), c.light(0.75).cg(0)] as CFArray, locations: [0, 1])!
                let spot = P(Double(box.midX) + (lx - Double(box.midX)) * 0.55, Double(box.midY) + (ly - Double(box.midY)) * 0.55)
                ctx.drawRadialGradient(glow, startCenter: spot, startRadius: 0, endCenter: spot, endRadius: radius * 0.32, options: [])
            }
        }
        ctx.restoreGState()
        roughEdge(path, c)
        if edge > 0 {
            ctx.saveGState(); ctx.translateBy(x: rng.range(-1.5...1.5), y: rng.range(-1.5...1.5))
            ctx.addPath(path); ctx.setStrokeColor(c.dark(0.45).cg(edge * 0.7)); ctx.setLineWidth(rng.range(2...4)); ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Broken, slightly feathered edges where the brush ran out of paint.
    func roughEdge(_ path: CGPath, _ c: Col) {
        for pass in 0..<3 {
            ctx.saveGState()
            ctx.translateBy(x: rng.range(-2.5...2.5), y: rng.range(-2.5...2.5))
            ctx.setLineDash(phase: rng.range(0...200), lengths: [rng.range(40...140), rng.range(8...40), rng.range(15...70), rng.range(5...25)])
            ctx.setStrokeColor((pass == 0 ? c : c.mix(c.light(0.1), rng.next())).cg(rng.range(0.15...0.35)))
            ctx.setLineWidth(rng.range(1.5...4)); ctx.addPath(path); ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Enlarges everything drawn afterwards around the centre, so subjects fill the frame.
    func zoom(_ s: Double, dy: Double = 0) {
        ctx.translateBy(x: W / 2, y: H / 2 + dy); ctx.scaleBy(x: s, y: s); ctx.translateBy(x: -W / 2, y: -H / 2)
    }

    /// A flat silhouette with only a little texture.
    func flat(_ path: CGPath, _ c: Col, texture: Double = 0.6) { shape(path, c, light: nil, texture: texture, edge: 0) }

    /// A painted line: several slightly offset passes of the brush.
    func line(_ path: CGPath, _ c: Col, width: Double, passes: Int = 3) {
        ctx.setLineWidth(width); ctx.setStrokeColor(c.cg()); ctx.addPath(path); ctx.strokePath()
        for _ in 0..<passes {
            ctx.saveGState()
            ctx.translateBy(x: rng.range(-1.5...1.5), y: rng.range(-1.5...1.5))
            ctx.setLineWidth(width * rng.range(0.35...0.8))
            ctx.setStrokeColor((rng.next() < 0.5 ? c.light(0.2) : c.dark(0.2)).cg(0.35))
            ctx.addPath(path); ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// A soft cast shadow beneath an object.
    func castShadow(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ bg: Col, strength: Double = 0.45) {
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy); ctx.scaleBy(x: 1, y: ry / rx)
        let g = CGGradient(colorsSpace: nil, colors: [bg.dark(0.55).cg(strength), bg.dark(0.55).cg(0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx, options: [])
        ctx.restoreGState()
    }

    func dot(_ x: Double, _ y: Double, _ r: Double, _ c: Col) {
        ctx.setFillColor(c.cg()); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    /// Canvas grain and a faint vignette, applied to the finished bitmap.
    func finish() -> CGImage {
        let vignette = CGGradient(colorsSpace: nil, colors: [Col("000000").cg(0), Col("000000").cg(0.22)] as CFArray, locations: [0.55, 1])!
        ctx.drawRadialGradient(vignette, startCenter: P(W / 2, H / 2), startRadius: 0, endCenter: P(W / 2, H / 2), endRadius: W * 0.62, options: [.drawsAfterEndLocation])
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * Int(H))
        var seed = rng.state | 1
        func noise() -> Int { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return Int(seed % 9) - 4 }
        let rows = (0..<Int(H)).map { _ in noise() }, columns = (0..<Int(W)).map { _ in noise() }
        for y in 0..<Int(H) {
            let row = data + y * ctx.bytesPerRow
            for x in 0..<Int(W) {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                let n = Int(seed % 21) - 10 + (x + y) % 2 * (rows[y] + columns[x]) / 2
                for k in 0..<3 { row[x * 4 + k] = UInt8(max(0, min(255, Int(row[x * 4 + k]) + n))) }
            }
        }
        return ctx.makeImage()!
    }
}

// MARK: - Reusable subjects

func leaf(_ p: Painter, at c: CGPoint, length L: Double, width w: Double, angle: Double, _ col: Col, vein: Bool = true) {
    let pts = place([(-L / 2, 0), (-L * 0.3, -w * 0.45), (0, -w / 2), (L * 0.3, -w * 0.32), (L / 2, 0), (L * 0.3, w * 0.32), (0, w / 2), (-L * 0.3, w * 0.45)], at: c, angle: angle)
    p.shape(smooth(pts), col, shine: 0.25, texture: 1.4, strokeAngle: angle)
    if vein { p.line(curve(place([(-L * 0.45, 0), (0, -w * 0.05), (L * 0.42, 0)], at: c, angle: angle)), col.dark(0.35), width: 3, passes: 1) }
}

func fish(_ p: Painter, at c: CGPoint, scale s: Double, angle a: Double = 0, body: Col, back: Col, flip: Bool = false) {
    let tail = place([(150, 0), (235, -70), (212, 0), (235, 70)], at: c, scale: s, angle: a, flip: flip)
    p.shape(smooth(tail), back, shine: 0.1)
    let bodyPath = smooth(place([(-215, 4), (-170, -40), (-70, -62), (60, -50), (150, -14), (168, 0), (150, 14), (60, 48), (-70, 58), (-170, 40)], at: c, scale: s, angle: a, flip: flip))
    p.shape(bodyPath, body, light: P(0, -0.6), shade: 0.3, shine: 0.55)
    p.ctx.saveGState(); p.ctx.addPath(bodyPath); p.ctx.clip()
    p.shape(smooth(place([(-230, -12), (-120, -50), (40, -52), (190, -22), (190, -70), (-230, -70)], at: c, scale: s, angle: a, flip: flip)), back, light: nil, texture: 1.5, edge: 0)
    p.ctx.restoreGState()
    p.line(curve(place([(-150, -38), (-135, 0), (-150, 36)], at: c, scale: s, angle: a, flip: flip)), body.dark(0.4), width: 4 * s, passes: 1)
    let eye = place([(-178, -8)], at: c, scale: s, angle: a, flip: flip)[0]
    p.dot(Double(eye.x), Double(eye.y), 15 * s, Col("f7f2e4")); p.dot(Double(eye.x), Double(eye.y), 8 * s, Col("1b1a1c"))
}

func checker(_ p: Painter, _ a: Col, _ b: Col, size: Double, from top: Double = 0) {
    p.ctx.setFillColor(a.cg()); p.ctx.fill(CGRect(x: 0, y: top, width: W, height: H - top))
    p.strokes(in: CGRect(x: 0, y: top, width: W, height: H - top), a, count: 1500, length: 30...90, width: 8...22, angle: 0.2)
    var y = top, row = 0
    while y < H {
        let h = size
        var x = Double(row % 2) * h
        while x < W { p.shape(rect(x, y, h, h), b, light: nil, texture: 0.9, edge: 0); x += h * 2 }
        y += h; row += 1
    }
}

// MARK: - Motifs

typealias Motif = (Painter, Int) -> Void
var motifs: [(String, Motif)] = []

motifs.append(("lemons", { p, v in
    let bg = v == 0 ? Col("1f4fa8") : Col("2f6b3a"), lemon = Col("f2cc2c")
    p.background(bg)
    p.zoom(1.35)
    for (x, y, a) in [(640.0, 540.0, -0.3), (900, 470, 0.25), (1060, 610, -0.1)] {
        p.castShadow(x + 20, y + 95, 170, 40, bg)
        let pts = (0..<12).map { i -> (Double, Double) in
            let t = Double(i) / 12 * 2 * .pi
            let tip = abs(cos(t)) > 0.99 ? 1.22 : 1
            return (cos(t) * 160 * tip, sin(t) * 112)
        }
        p.shape(smooth(place(pts, at: P(x, y), angle: a)), lemon, shade: 0.42, shine: 0.5)
    }
    leaf(p, at: P(780, 390), length: 240, width: 95, angle: -0.8, Col("3d8a3f"))
    leaf(p, at: P(990, 380), length: 200, width: 80, angle: 0.5, Col("2f7a38"))
}))

motifs.append(("pear", { p, v in
    let bg = v == 0 ? Col("e8531f") : Col("9b86c7"), pear = v == 0 ? Col("b7c436") : Col("e2b93b")
    p.background(bg)
    p.zoom(1.25)
    let c = P(836, 520)
    p.castShadow(870, 790, 230, 45, bg)
    p.shape(smooth(place([(0, -250), (48, -215), (62, -130), (110, -20), (175, 95), (165, 195), (95, 250), (0, 268), (-95, 250), (-165, 195), (-175, 95), (-110, -20), (-62, -130), (-48, -215)], at: c)), pear, shade: 0.45, shine: 0.45)
    p.line(curve([P(836, 275), P(846, 220), P(870, 180)]), Col("5a3a22"), width: 14)
    leaf(p, at: P(930, 215), length: 170, width: 70, angle: -0.35, Col("3d8a3f"))
}))

motifs.append(("cherries", { p, v in
    let bg = v == 0 ? Col("f2a3b5") : Col("efe3c8"), cherry = Col("b3161f")
    p.background(bg)
    p.zoom(1.2)
    p.line(curve([P(720, 600), P(760, 420), P(850, 250), P(900, 200)]), Col("4f7a2a"), width: 11)
    p.line(curve([P(990, 640), P(960, 440), P(920, 280), P(900, 200)]), Col("4f7a2a"), width: 11)
    for (x, y) in [(720.0, 660.0), (990, 700)] {
        p.castShadow(x + 30, y + 110, 130, 30, bg)
        p.shape(p.blob(x, y, 118, 108, wobble: 0.05), cherry, shade: 0.5, shine: 0.6)
    }
    leaf(p, at: P(990, 190), length: 230, width: 90, angle: -0.25, Col("4f8f33"))
}))

motifs.append(("oranges", { p, v in
    let bg = v == 0 ? Col("1d7f7a") : Col("1f4fa8"), rind = Col("ee7d16"), flesh = Col("f7a531")
    p.background(bg)
    p.zoom(1.25)
    p.castShadow(1150, 700, 230, 60, bg)
    p.shape(p.blob(1130, 520, 215, 205), rind, shade: 0.45, shine: 0.4)
    for (x, y) in [(640.0, 560.0)] {
        p.castShadow(x + 20, y + 190, 250, 50, bg)
        p.shape(p.blob(x, y, 225, 215, wobble: 0.015), rind, light: nil, edge: 0.3)
        p.shape(p.blob(x, y, 196, 187, wobble: 0.015), Col("fbe3b0"), light: nil, texture: 0.5, edge: 0)
        p.shape(p.blob(x, y, 182, 173, wobble: 0.015), flesh, light: P(-0.3, -0.4), shade: 0.2, shine: 0.3, edge: 0)
        for i in 0..<10 {
            let a = Double(i) / 10 * 2 * .pi + 0.2
            p.line(curve([P(x + cos(a) * 18, y + sin(a) * 18), P(x + cos(a) * 176, y + sin(a) * 168)]), Col("fbe3b0"), width: 7, passes: 1)
        }
        p.dot(x, y, 20, Col("fbe3b0"))
    }
    leaf(p, at: P(1150, 300), length: 210, width: 85, angle: -0.6, Col("2f6b3a"))
}))

motifs.append(("fish-plate", { p, v in
    let a = v == 0 ? Col("efe3c8") : Col("f4e6c4"), b = v == 0 ? Col("1f4fa8") : Col("2f6b3a")
    checker(p, a, b, size: 105)
    p.zoom(1.2)
    p.castShadow(850, 520, 520, 330, a, strength: 0.5)
    // A strong plate colour keeps the clock legible; a pale plate would sit right behind the digits.
    let plate = v == 0 ? Col("d0572a") : Col("2c3f8f")
    p.shape(p.blob(836, 480, 470, 300, wobble: 0.01), plate, light: P(-0.3, -0.4), shade: 0.3, shine: 0.25)
    p.shape(p.blob(836, 480, 390, 240, wobble: 0.01), plate.dark(0.12), light: P(0.3, 0.4), shade: 0.25, shine: 0, edge: 0.12)
    fish(p, at: P(836, 420), scale: 1.25, angle: -0.08, body: Col("aebfd0"), back: Col("3e5a7a"))
    fish(p, at: P(820, 560), scale: 1.15, angle: 0.06, body: Col("b9c7d4"), back: Col("35506e"), flip: true)
    p.shape(p.blob(1110, 610, 70, 62), Col("f2cc2c"), light: P(-0.3, -0.4))
    p.shape(p.blob(1110, 610, 54, 47), Col("f8e27a"), light: nil, edge: 0)
}))

motifs.append(("window-plant", { p, v in
    let hue = v == 0 ? Col("2c3f8f") : Col("a8471f")
    p.background(hue.dark(0.35))
    // Light falling through the window onto the wall.
    p.flat(polygon([P(120, 150), P(560, 90), P(560, 640), P(120, 720)]), hue.light(0.12), texture: 0.4)
    for i in 1..<3 { p.flat(rect(120 + Double(i) * 147, 90, 22, 640), hue.dark(0.3), texture: 0.3) }
    p.flat(rect(760, 110, 620, 560), hue.light(0.38))
    p.strokes(in: CGRect(x: 760, y: 110, width: 620, height: 560), hue.light(0.38), count: 500, length: 40...120, width: 8...26, angle: -0.7)
    p.flat(rect(1052, 110, 26, 560), hue.dark(0.25)); p.flat(rect(760, 372, 620, 26), hue.dark(0.25))
    p.flat(rect(730, 668, 680, 40), hue.dark(0.45))
    let plant = hue.dark(0.62), base = P(1065, 590)
    for (a, l) in [(-2.6, 190.0), (-2.15, 230), (-1.75, 250), (-1.4, 240), (-1.0, 220), (-0.55, 180)] {
        let tipBase = P(Double(base.x) + cos(a) * 95, Double(base.y) + sin(a) * 95)
        p.line(curve([base, tipBase]), plant, width: 8, passes: 1)
        leaf(p, at: P(Double(tipBase.x) + cos(a) * l / 2, Double(tipBase.y) + sin(a) * l / 2), length: l, width: l * 0.36, angle: a, plant, vein: false)
    }
    p.shape(smooth([P(975, 585), P(1155, 585), P(1135, 668), P(995, 668)]), plant, light: nil, edge: 0)
}))

motifs.append(("moon-sea", { p, v in
    let sky = v == 0 ? Col("16254f") : Col("c8201e"), sea = v == 0 ? Col("0f1b38") : Col("7e1414"), moon = Col("f6e7b8")
    p.background(sky, angle: 0.05)
    let glow = CGGradient(colorsSpace: nil, colors: [moon.cg(0.35), moon.cg(0)] as CFArray, locations: [0, 1])!
    p.ctx.drawRadialGradient(glow, startCenter: P(1230, 230), startRadius: 0, endCenter: P(1230, 230), endRadius: 330, options: [])
    p.shape(p.blob(1230, 230, 105, 105, wobble: 0.012), moon, light: P(-0.3, -0.3), shade: 0.15, shine: 0.2, edge: 0)
    p.flat(rect(0, 640, W, H - 640), sea)
    p.strokes(in: CGRect(x: 0, y: 640, width: W, height: H - 640), sea, count: 700, length: 60...220, width: 4...12, angle: 0, spread: 0.04, jitter: 0.18)
    for i in 0..<34 {
        let y = 650 + Double(i) * 8.5, w = 30 + Double(i) * 4 + p.rng.range(0...60)
        p.ctx.setStrokeColor(moon.cg(0.75 - Double(i) * 0.018)); p.ctx.setLineWidth(4)
        p.ctx.move(to: P(1230 - w / 2 + p.rng.range(-20...20), y)); p.ctx.addLine(to: P(1230 + w / 2 + p.rng.range(-20...20), y)); p.ctx.strokePath()
    }
    p.flat(polygon([P(360, 632), P(470, 632), P(450, 650), P(380, 650)]), sea.dark(0.5))
    p.flat(polygon([P(415, 628), P(415, 540), P(460, 626)]), sea.dark(0.5))
}))

motifs.append(("black-cat", { p, v in
    let bg = v == 0 ? Col("e0a91f") : Col("1d7f7a"), cat = Col("1b1a1d"), c = P(836, 540)
    p.background(bg)
    p.zoom(1.15)
    p.castShadow(836, 800, 260, 45, bg)
    p.line(curve(place([(150, 210), (290, 180), (330, 60), (280, -30)], at: c)), cat, width: 38, passes: 1)
    p.shape(smooth(place([(0, -150), (95, -110), (155, 30), (175, 200), (90, 255), (0, 262), (-90, 255), (-175, 200), (-155, 30), (-95, -110)], at: c)), cat, shade: 0.2, shine: 0.12)
    for side in [-1.0, 1.0] { p.shape(polygon(place([(side * 105, -255), (side * 95, -385), (side * 20, -320)], at: c)), cat, light: nil, edge: 0) }
    p.shape(p.blob(836, 300, 118, 100), cat, shade: 0.2, shine: 0.12, edge: 0)
    for side in [-1.0, 1.0] {
        p.shape(p.blob(836 + side * 48, 292, 30, 18, wobble: 0.01), Col("e9cf3b"), light: nil, edge: 0)
        p.shape(p.blob(836 + side * 48, 292, 6, 16, wobble: 0.01), cat, light: nil, edge: 0)
    }
    p.dot(836, 330, 8, Col("d48a95"))
    let bow = v == 0 ? Col("c8201e") : Col("f2a3b5")
    p.shape(polygon([P(836, 410), P(770, 375), P(770, 445)]), bow, light: nil)
    p.shape(polygon([P(836, 410), P(902, 375), P(902, 445)]), bow, light: nil)
    p.dot(836, 410, 16, bow.dark(0.2))
}))

motifs.append(("two-figures", { p, v in
    let bg = v == 0 ? Col("2f6b3a") : Col("e8531f"), door = v == 0 ? Col("e9d9a6") : Col("f2c9a0")
    p.background(bg)
    p.zoom(1.12)
    let arch = CGMutablePath()
    arch.move(to: P(640, 820)); arch.addLine(to: P(640, 360)); arch.addArc(center: P(800, 360), radius: 160, startAngle: .pi, endAngle: 0, clockwise: false)
    arch.addLine(to: P(960, 820)); arch.closeSubpath()
    p.shape(arch, door, light: nil, texture: 0.8, edge: 0)
    let figures: [(Double, Col)] = [(760, bg.dark(0.72)), (945, v == 0 ? Col("c8201e") : Col("1f4fa8"))]
    for (x, col) in figures {
        p.shape(smooth(place([(-26, -195), (26, -195), (30, -160), (88, -135), (100, 0), (90, 300), (-90, 300), (-100, 0), (-88, -135), (-30, -160)], at: P(x, 520))), col, light: nil, texture: 0.8, edge: 0)
        p.shape(p.blob(x, 268, 66, 78), col, light: nil, edge: 0)
    }
}))

motifs.append(("frog-crown", { p, v in
    let bg = v == 0 ? Col("f2a3b5") : Col("7fb6de"), frog = Col("4f9a3a"), belly = Col("b9d67a")
    p.background(bg)
    p.zoom(1.1)
    p.castShadow(836, 860, 360, 60, bg)
    for side in [-1.0, 1.0] { p.shape(p.blob(836 + side * 250, 800, 120, 60), frog.dark(0.1)) }
    p.shape(p.blob(836, 610, 290, 250), frog, shade: 0.35, shine: 0.3)
    p.shape(p.blob(836, 690, 180, 150), belly, light: P(-0.2, -0.5), shade: 0.2)
    for side in [-1.0, 1.0] {
        p.shape(p.blob(836 + side * 150, 380, 78, 74), frog, shade: 0.3, edge: 0.2)
        p.dot(836 + side * 150, 380, 44, Col("f7f2e4")); p.dot(836 + side * 146, 386, 24, Col("1b1a1c")); p.dot(836 + side * 138, 375, 7, Col("ffffff"))
    }
    p.line(curve([P(700, 500), P(836, 545), P(972, 500)]), frog.dark(0.5), width: 7, passes: 1)
    for side in [-1.0, 1.0] { p.dot(836 + side * 55, 460, 7, frog.dark(0.5)) }
    let gold = Col("e8b923")
    p.shape(polygon([P(730, 330), P(730, 230), P(775, 280), P(836, 200), P(897, 280), P(942, 230), P(942, 330)]), gold, shade: 0.3, shine: 0.5)
    for (x, y, c) in [(836.0, 290.0, Col("c8201e")), (775, 305, Col("1f4fa8")), (897, 305, Col("1f4fa8"))] { p.dot(x, y, 12, c) }
}))

motifs.append(("fried-eggs", { p, v in
    let bg = v == 0 ? Col("1f4fa8") : Col("c8201e"), pan = Col("222326")
    p.background(bg)
    p.zoom(1.15)
    p.castShadow(790, 560, 400, 330, bg, strength: 0.5)
    p.line(curve([P(1080, 520), P(1500, 470)]), pan, width: 64, passes: 2)
    p.shape(p.blob(760, 480, 360, 360, wobble: 0.005), pan, light: P(-0.3, -0.4), shade: 0.3, shine: 0.18)
    p.shape(p.blob(760, 480, 315, 315, wobble: 0.005), pan.light(0.08), light: P(0.3, 0.4), shade: 0.3, shine: 0.1, edge: 0)
    for (x, y) in [(640.0, 420.0), (870, 580)] {
        p.shape(p.blob(x, y, 150, 130, wobble: 0.16), Col("f7f2e6"), light: P(-0.3, -0.4), shade: 0.18, shine: 0.3, edge: 0.1)
        p.shape(p.blob(x + 10, y - 5, 58, 55, wobble: 0.02), Col("f5a80f"), shade: 0.35, shine: 0.7)
    }
}))

motifs.append(("teacup", { p, v in
    let wall = v == 0 ? Col("e8531f") : Col("9b86c7"), cloth = v == 0 ? Col("c8201e") : Col("2c3f8f")
    p.background(wall)
    checker(p, Col("f3ead6"), cloth, size: 62, from: 600)
    p.zoom(1.15)
    p.castShadow(860, 660, 300, 60, Col("f3ead6"), strength: 0.5)
    p.shape(p.blob(836, 640, 280, 62, wobble: 0.005), Col("f6f1e5"), light: P(-0.2, -0.5), shade: 0.2)
    p.line(curve([P(1000, 470), P(1090, 470), P(1090, 560), P(1000, 580)]), Col("f6f1e5"), width: 26)
    let cup = CGMutablePath()
    cup.move(to: P(640, 440)); cup.addCurve(to: P(836, 640), control1: P(640, 580), control2: P(720, 640))
    cup.addCurve(to: P(1032, 440), control1: P(952, 640), control2: P(1032, 580)); cup.closeSubpath()
    p.shape(cup, Col("f6f1e5"), light: P(-0.4, -0.2), shade: 0.35, shine: 0.3)
    p.shape(p.blob(836, 440, 196, 40, wobble: 0.004), Col("8a4a22"), light: P(0.3, 0.3), shade: 0.2, shine: 0.1)
    p.line(curve([P(700, 520), P(836, 560), P(972, 520)]), cloth, width: 12, passes: 1)
    for x in [760.0, 850, 930] {
        p.ctx.setStrokeColor(Col("ffffff").cg(0.35))
        p.ctx.setLineWidth(10); p.ctx.addPath(curve([P(x, 380), P(x + 30, 320), P(x - 20, 260), P(x + 15, 190)])); p.ctx.strokePath()
    }
}))

motifs.append(("mushrooms", { p, v in
    let bg = v == 0 ? Col("2f6b3a") : Col("16254f"), cap = Col("c8201e"), stem = Col("f1e6cc")
    p.background(bg)
    p.zoom(1.3)
    for (x, y, s) in [(640.0, 560.0, 0.8), (870, 500, 1.1), (1080, 600, 0.7)] {
        p.castShadow(x, y + 250 * s, 170 * s, 30 * s, bg)
        p.shape(smooth(place([(-55, 0), (55, 0), (70, 240), (-70, 240)], at: P(x, y), scale: s)), stem, light: P(-0.4, 0), shade: 0.3)
        let capPath = CGMutablePath()
        capPath.move(to: P(x - 200 * s, y + 20 * s))
        capPath.addCurve(to: P(x + 200 * s, y + 20 * s), control1: P(x - 190 * s, y - 230 * s), control2: P(x + 190 * s, y - 230 * s))
        capPath.addQuadCurve(to: P(x - 200 * s, y + 20 * s), control: P(x, y + 60 * s)); capPath.closeSubpath()
        p.shape(capPath, cap, light: P(-0.3, -0.5), shade: 0.4, shine: 0.45)
        for (dx, dy, r) in [(-110.0, -40.0, 22.0), (-30, -120, 28), (70, -70, 24), (130, -10, 16), (-10, -30, 18), (-150, 0, 12)] {
            p.shape(p.blob(x + dx * s, y + dy * s, r * s, r * s * 0.85), Col("f7f0dd"), light: nil, edge: 0)
        }
    }
}))

motifs.append(("cactus", { p, v in
    let bg = v == 0 ? Col("f2a3b5") : Col("e0a91f"), green = Col("3f7d4a"), pot = Col("c0592b")
    p.background(bg)
    p.zoom(1.1)
    p.castShadow(870, 850, 260, 40, bg)
    let body = CGPath(roundedRect: CGRect(x: 770, y: 250, width: 140, height: 470), cornerWidth: 70, cornerHeight: 70, transform: nil)
    p.shape(body, green, light: P(-0.4, 0), shade: 0.4, shine: 0.3)
    p.shape(CGPath(roundedRect: CGRect(x: 640, y: 400, width: 90, height: 220), cornerWidth: 45, cornerHeight: 45, transform: nil), green, light: P(-0.4, 0))
    p.shape(CGPath(roundedRect: CGRect(x: 690, y: 560, width: 110, height: 60), cornerWidth: 30, cornerHeight: 30, transform: nil), green, light: nil, edge: 0)
    p.shape(CGPath(roundedRect: CGRect(x: 950, y: 330, width: 90, height: 230), cornerWidth: 45, cornerHeight: 45, transform: nil), green, light: P(-0.4, 0))
    p.shape(CGPath(roundedRect: CGRect(x: 880, y: 500, width: 120, height: 60), cornerWidth: 30, cornerHeight: 30, transform: nil), green, light: nil, edge: 0)
    for x in [810.0, 840, 870] { p.line(curve([P(x, 275), P(x, 700)]), green.dark(0.3), width: 4, passes: 1) }
    p.shape(p.blob(840, 245, 34, 30), Col("f06a8a"), light: nil)
    p.shape(polygon([P(680, 700), P(1000, 700), P(960, 870), P(720, 870)]), pot, light: P(-0.4, 0), shade: 0.35)
    p.shape(rect(660, 680, 360, 60), pot.light(0.08), light: P(-0.4, -0.3), shade: 0.25)
}))

motifs.append(("tulips", { p, v in
    let bg = v == 0 ? Col("1f4fa8") : Col("e8531f"), vase = v == 0 ? Col("f1e6cc") : Col("1f4fa8")
    p.background(bg)
    p.zoom(1.12)
    let heads: [(Double, Double, Col)] = [(700, 300, Col("c8201e")), (850, 230, Col("f2cc2c")), (990, 320, Col("f2a3b5")), (780, 400, Col("e8531f"))]
    for (x, y, _) in heads { p.line(curve([P(836, 620), P((836 + x) / 2, (620 + y) / 2 + 40), P(x, y + 40)]), Col("3f7d4a"), width: 12) }
    leaf(p, at: P(740, 520), length: 260, width: 70, angle: -2.2, Col("3f7d4a"))
    leaf(p, at: P(940, 510), length: 250, width: 70, angle: -0.9, Col("4a8a3f"))
    for (x, y, c) in heads {
        p.shape(smooth(place([(-55, -60), (-25, -20), (0, -70), (25, -20), (55, -60), (60, 20), (0, 70), (-60, 20)], at: P(x, y))), c, shade: 0.4, shine: 0.4)
    }
    p.castShadow(860, 880, 220, 35, bg)
    p.shape(smooth(place([(-70, -250), (70, -250), (80, -200), (150, -60), (150, 60), (100, 120), (-100, 120), (-150, 60), (-150, -60), (-80, -200)], at: P(836, 760))), vase, shade: 0.4, shine: 0.4)
}))

motifs.append(("goldfish-bowl", { p, v in
    let bg = v == 0 ? Col("e0a91f") : Col("c8201e"), water = Col("9fd0d6")
    p.background(bg)
    p.zoom(1.25)
    p.castShadow(836, 810, 300, 45, bg)
    let bowl = p.blob(836, 500, 300, 290, wobble: 0.005)
    p.ctx.saveGState(); p.ctx.addPath(bowl); p.ctx.clip()
    p.shape(rect(500, 330, 700, 500), water, light: P(-0.4, -0.3), shade: 0.35, shine: 0.3, edge: 0)
    p.ctx.restoreGState()
    p.ctx.addPath(bowl); p.ctx.setStrokeColor(Col("ffffff").cg(0.45)); p.ctx.setLineWidth(6); p.ctx.strokePath()
    p.shape(p.blob(836, 330, 230, 22, wobble: 0.004), water.light(0.4), light: nil, edge: 0.2)
    fish(p, at: P(830, 540), scale: 0.62, angle: -0.1, body: Col("f08a1c"), back: Col("e2561b"))
    for (x, y, r) in [(700.0, 460.0, 10.0), (715, 410, 7), (705, 370, 5)] {
        p.ctx.setStrokeColor(Col("ffffff").cg(0.7)); p.ctx.setLineWidth(3); p.ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    p.ctx.setStrokeColor(Col("ffffff").cg(0.5)); p.ctx.setLineWidth(18)
    p.ctx.addPath(curve([P(620, 420), P(600, 520), P(640, 640)])); p.ctx.strokePath()
}))

motifs.append(("sun-hills", { p, v in
    let sky = v == 0 ? Col("f2a3b5") : Col("7fb6de"), sun = v == 0 ? Col("e8531f") : Col("f2cc2c")
    let hills = v == 0 ? [Col("c8201e"), Col("8f1d2c"), Col("4f1224")] : [Col("5a9a4a"), Col("2f6b3a"), Col("1d3f2a")]
    p.background(sky, angle: 0.05)
    p.shape(p.blob(836, 360, 190, 190, wobble: 0.01), sun, light: nil, texture: 0.8, edge: 0)
    for (i, c) in hills.enumerated() {
        let base = 520 + Double(i) * 120
        var pts = [P(-40, H + 40)]
        for k in 0...8 { pts.append(P(Double(k) * W / 8, base + sin(Double(k) * 1.3 + Double(i) * 2) * 60)) }
        pts.append(P(W + 40, H + 40))
        let path = CGMutablePath(); path.addPath(curve(Array(pts.dropFirst().dropLast())))
        path.addLine(to: P(W + 40, H + 40)); path.addLine(to: P(-40, H + 40)); path.closeSubpath()
        p.shape(path, c, light: nil, texture: 0.8, strokeAngle: 0.1, edge: 0)
    }
}))

motifs.append(("sailboat", { p, v in
    let sky = v == 0 ? Col("efe3c8") : Col("f2a3b5"), sea = v == 0 ? Col("1f4fa8") : Col("1d7f7a"), sail = v == 0 ? Col("c8201e") : Col("f2cc2c")
    p.background(sky, angle: 0.05)
    p.shape(p.blob(1250, 220, 80, 80), v == 0 ? Col("e8531f") : Col("f7f0dd"), light: nil, edge: 0)
    p.flat(rect(0, 610, W, H - 610), sea)
    p.strokes(in: CGRect(x: 0, y: 610, width: W, height: H - 610), sea, count: 600, length: 60...200, width: 5...14, angle: 0, spread: 0.05, jitter: 0.2)
    p.line(curve([P(840, 600), P(840, 170)]), Col("3b2a20"), width: 10)
    p.shape(polygon([P(855, 180), P(855, 570), P(1100, 570)]), sail, light: P(0.4, 0), shade: 0.3, shine: 0.2)
    p.shape(polygon([P(825, 210), P(825, 570), P(640, 570)]), Col("f7f0dd"), light: P(-0.4, 0), shade: 0.25)
    p.shape(smooth([P(600, 590), P(1120, 590), P(1040, 670), P(840, 685), P(680, 670)]), Col("3b2a20"), light: P(0, -0.5), shade: 0.3, shine: 0.2)
}))

motifs.append(("watermelon", { p, v in
    let bg = v == 0 ? Col("1d7f7a") : Col("e0a91f")
    p.background(bg)
    p.zoom(1.3)
    for (x, y, a) in [(700.0, 520.0, -0.25), (1000, 560, 0.3)] {
        p.castShadow(x + 20, y + 150, 250, 40, bg)
        func wedge(_ r: Double) -> CGPath {
            let path = CGMutablePath(); path.move(to: P(x, y - 200 + 0))
            path.addArc(center: P(x, y - 200), radius: r, startAngle: .pi / 2 - 0.62 + a, endAngle: .pi / 2 + 0.62 + a, clockwise: false)
            path.closeSubpath(); return path
        }
        p.shape(wedge(360), Col("2f6b3a"), light: P(-0.3, 0), shade: 0.3)
        p.shape(wedge(335), Col("e9efc9"), light: nil, edge: 0)
        p.shape(wedge(315), Col("e2333f"), light: P(-0.2, -0.4), shade: 0.3, shine: 0.3, edge: 0)
        for i in 0..<9 {
            let t = .pi / 2 - 0.45 + a + Double(i % 5) * 0.22, r = 190 + Double(i / 5) * 70
            p.shape(p.blob(x + cos(t) * r, y - 200 + sin(t) * r, 7, 12, angle: t), Col("1b1a1c"), light: nil, edge: 0)
        }
    }
}))

motifs.append(("plums", { p, v in
    let bg = v == 0 ? Col("e8531f") : Col("efe3c8"), bowl = v == 0 ? Col("1f4fa8") : Col("2f6b3a"), plum = Col("5b2a6e")
    p.background(bg)
    p.zoom(1.25)
    p.castShadow(836, 800, 380, 50, bg)
    for (x, y) in [(700.0, 470.0), (836, 430), (970, 470), (770, 380), (910, 370)] {
        p.shape(p.blob(x, y, 100, 92, wobble: 0.04), plum, shade: 0.45, shine: 0.45)
        p.line(curve([P(x, y - 90), P(x + 8, y - 120)]), Col("4a3322"), width: 7, passes: 1)
    }
    let bowlPath = CGMutablePath()
    bowlPath.move(to: P(520, 480)); bowlPath.addLine(to: P(1152, 480))
    bowlPath.addCurve(to: P(836, 790), control1: P(1140, 700), control2: P(1000, 790))
    bowlPath.addCurve(to: P(520, 480), control1: P(672, 790), control2: P(532, 700)); bowlPath.closeSubpath()
    p.shape(bowlPath, bowl, light: P(-0.4, -0.3), shade: 0.4, shine: 0.3)
    for y in [560.0, 640] { p.line(curve([P(560, y), P(836, y + 30), P(1110, y)]), Col("f7f0dd"), width: 8, passes: 1) }
}))

motifs.append(("martini", { p, v in
    let bg = v == 0 ? Col("c8201e") : Col("16254f"), glass = Col("dfeef0")
    p.background(bg)
    p.zoom(1.1)
    p.castShadow(836, 830, 170, 30, bg)
    p.shape(p.blob(836, 810, 130, 24, wobble: 0.004), glass, light: nil, edge: 0.3)
    p.line(curve([P(836, 800), P(836, 520)]), glass, width: 16, passes: 1)
    p.ctx.saveGState(); p.ctx.setAlpha(0.8)
    p.shape(polygon([P(600, 250), P(1072, 250), P(836, 520)]), glass, light: P(-0.4, 0), shade: 0.2, shine: 0.3)
    p.ctx.restoreGState()
    p.shape(polygon([P(640, 290), P(1032, 290), P(836, 490)]), Col("e9efc9"), light: P(0.3, 0.3), shade: 0.2, edge: 0)
    p.line(curve([P(760, 170), P(900, 420)]), Col("3b2a20"), width: 6, passes: 1)
    p.shape(p.blob(840, 350, 42, 36), Col("6f8a2a"), shade: 0.4, shine: 0.5)
    p.shape(p.blob(826, 344, 14, 12), Col("c8201e"), light: nil, edge: 0)
}))

motifs.append(("dachshund", { p, v in
    let bg = v == 0 ? Col("e0a91f") : Col("7fb6de"), dog = Col("7a3f1d"), jumper = v == 0 ? Col("c8201e") : Col("e8531f")
    p.background(bg)
    p.zoom(1.12)
    p.castShadow(836, 790, 420, 40, bg)
    for x in [560.0, 620, 1040, 1100] { p.shape(CGPath(roundedRect: CGRect(x: x, y: 600, width: 50, height: 180), cornerWidth: 22, cornerHeight: 22, transform: nil), dog.dark(0.15), light: nil) }
    p.line(curve([P(500, 520), P(420, 460), P(400, 400)]), dog, width: 26, passes: 1)
    p.shape(CGPath(roundedRect: CGRect(x: 480, y: 440, width: 700, height: 220), cornerWidth: 110, cornerHeight: 110, transform: nil), dog, light: P(0, -0.5), shade: 0.35, shine: 0.25)
    p.ctx.saveGState(); p.ctx.addPath(CGPath(roundedRect: CGRect(x: 480, y: 440, width: 700, height: 220), cornerWidth: 110, cornerHeight: 110, transform: nil)); p.ctx.clip()
    p.shape(rect(640, 420, 420, 260), jumper, light: P(0, -0.5), shade: 0.3, edge: 0)
    for x in stride(from: 660.0, to: 1060, by: 60) { p.line(curve([P(x, 430), P(x, 680)]), jumper.light(0.5), width: 10, passes: 1) }
    p.ctx.restoreGState()
    p.shape(smooth([P(1110, 480), P(1190, 380), P(1300, 400), P(1400, 470), P(1390, 510), P(1280, 520), P(1180, 560)]), dog, light: P(0, -0.5), shade: 0.3)
    p.shape(smooth([P(1190, 400), P(1240, 410), P(1250, 560), P(1200, 580), P(1170, 480)]), dog.dark(0.3), light: nil)
    p.dot(1400, 482, 16, Col("1b1a1c")); p.dot(1300, 440, 10, Col("1b1a1c"))
}))

motifs.append(("snail", { p, v in
    let bg = v == 0 ? Col("2f6b3a") : Col("9b86c7"), shell = v == 0 ? Col("e0a91f") : Col("e8531f"), body = Col("d9c3a0")
    p.background(bg)
    p.zoom(1.22)
    p.castShadow(836, 720, 420, 40, bg)
    p.shape(smooth([P(480, 700), P(560, 640), P(1100, 640), P(1250, 560), P(1290, 480), P(1330, 500), P(1300, 640), P(1180, 710)]), body, light: P(0, -0.5), shade: 0.3, shine: 0.3)
    for (x, y) in [(1275.0, 400.0), (1325, 410)] {
        p.line(curve([P(1300, 500), P(x, y)]), body.dark(0.1), width: 12, passes: 1); p.dot(x, y, 16, body.dark(0.35))
    }
    p.shape(p.blob(820, 470, 230, 220, wobble: 0.02), shell, shade: 0.45, shine: 0.45)
    var spiral: [CGPoint] = []
    for i in 0..<60 { let t = Double(i) * 0.24, r = 200 - Double(i) * 3.2; spiral.append(P(830 + cos(t) * r, 475 + sin(t) * r)) }
    p.line(curve(spiral), shell.dark(0.45), width: 12, passes: 1)
}))

motifs.append(("swan", { p, v in
    let bg = v == 0 ? Col("1d7f7a") : Col("16254f"), water = bg.dark(0.35), swan = Col("f6f1e5")
    p.background(bg)
    p.flat(rect(0, 650, W, H - 650), water)
    p.strokes(in: CGRect(x: 0, y: 650, width: W, height: H - 650), water, count: 500, length: 60...200, width: 5...12, angle: 0, spread: 0.05, jitter: 0.2)
    p.zoom(1.15, dy: 40)
    p.line(curve([P(980, 600), P(1020, 440), P(960, 320), P(900, 260), P(930, 190)]), swan, width: 44, passes: 2)
    p.shape(p.blob(935, 190, 52, 44), swan, light: P(-0.3, -0.4), edge: 0.15)
    p.shape(polygon([P(880, 180), P(820, 215), P(885, 210)]), Col("e8531f"), light: nil)
    p.dot(920, 180, 7, Col("1b1a1c"))
    p.shape(smooth([P(640, 600), P(720, 480), P(900, 470), P(1060, 520), P(1120, 610), P(1000, 680), P(760, 680)]), swan, shade: 0.3, shine: 0.3)
    p.shape(smooth([P(700, 580), P(760, 500), P(900, 500), P(960, 560), P(880, 620), P(760, 630)]), swan.dark(0.08), light: nil, edge: 0.15)
}))

motifs.append(("strawberries", { p, v in
    let bg = v == 0 ? Col("7fb6de") : Col("efe3c8"), berry = Col("d3202a")
    p.background(bg)
    p.zoom(1.2)
    for (x, y, a) in [(650.0, 520.0, -0.35), (850, 470, 0.05), (1040, 540, 0.4)] {
        p.castShadow(x + 20, y + 175, 130, 30, bg)
        let body = smooth(place([(-110, -90), (-40, -118), (40, -118), (110, -90), (122, 0), (72, 110), (0, 165), (-72, 110), (-122, 0)], at: P(x, y), angle: a))
        p.shape(body, berry, shade: 0.45, shine: 0.5)
        for (sx, sy) in [(-60.0, -60.0), (0, -70), (60, -60), (-80, 0), (-25, -10), (30, -15), (85, 0), (-45, 55), (15, 50), (60, 60), (-10, 110)] {
            let pt = place([(sx, sy)], at: P(x, y), angle: a)[0]
            p.shape(p.blob(Double(pt.x), Double(pt.y), 5, 9, angle: a), Col("f5d66a"), light: nil, edge: 0)
        }
        for k in 0..<6 {
            let t = -Double.pi / 2 + (Double(k) - 2.5) * 0.5 + a
            let top = place([(0, -112)], at: P(x, y), angle: a)[0]
            leaf(p, at: P(Double(top.x) + cos(t) * 40, Double(top.y) + sin(t) * 22), length: 90, width: 34, angle: t, Col("3d8a3f"), vein: false)
        }
    }
}))

// MARK: - Render

try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var rendered: [(String, CGImage)] = []
for (index, (name, motif)) in motifs.enumerated() {
    for variant in 0..<2 {
        let file = "painted-\(name)-\(variant + 1)"
        if let filter, !file.contains(filter) { continue }
        let painter = Painter(seed: UInt64(index * 2 + variant + 1) &* 7919)
        // The second version of each subject is mirrored, so the pair reads as two compositions.
        if variant == 1 { painter.ctx.translateBy(x: W, y: 0); painter.ctx.scaleBy(x: -1, y: 1) }
        motif(painter, variant)
        let image = painter.finish()
        let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.86])!
        try! data.write(to: output.appendingPathComponent(file + ".jpg"))
        rendered.append((file, image))
    }
}

// A contact sheet for reviewing the whole set at once.
let columns = 5, tileW = 320.0, tileH = 180.0
let rows = (rendered.count + columns - 1) / columns
let sheet = CGContext(data: nil, width: Int(tileW) * columns, height: Int(tileH) * rows, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for (i, (_, image)) in rendered.enumerated() {
    let x = Double(i % columns) * tileW, y = Double(rows - 1 - i / columns) * tileH
    sheet.draw(image, in: CGRect(x: x + 2, y: y + 2, width: tileW - 4, height: tileH - 4))
}
// Kept out of the output folder, which the app treats as its wallpaper list.
let preview = FileManager.default.temporaryDirectory.appendingPathComponent("stopwatch-backgrounds-preview.jpg")
try! NSBitmapImageRep(cgImage: sheet.makeImage()!).representation(using: .jpeg, properties: [.compressionFactor: 0.8])!.write(to: preview)
print("Preview: \(preview.path)")
print("Rendered \(rendered.count) images")
