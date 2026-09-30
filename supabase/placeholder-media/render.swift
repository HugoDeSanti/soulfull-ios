// Placeholder somatic video for Soulfull test builds.
//
//   render <fonts-dir> <out-silent.mp4>             draw + encode the animation
//   mux <video.mp4> <audio.m4a> <out.mp4>           add the soundtrack
//   optimize <in.m4a> <out.m4a>                     moov-first passthrough
//   frame <fonts-dir> <t> <out.png>                 one still, for checking poses

import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W = 720, H = 1280, FPS: Int32 = 30
let DURATION = 60.0

// MARK: - Palette (Theme.swift, converted to CGColor)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let bgTop = rgb(0.063, 0.069, 0.039)      // Theme.bgDeep
let bgBottom = rgb(0.043, 0.047, 0.027)   // Theme.bg
let glow = rgb(0.244, 0.263, 0.082, 0.55) // Theme.accent
let ink = rgb(0.961, 0.953, 0.910)        // Theme.ink
let inkSoft = rgb(0.788, 0.773, 0.690)    // Theme.inkSoft
let skin = rgb(0.80, 0.63, 0.49)
let skinShade = rgb(0.72, 0.55, 0.42)
let hair = rgb(0.33, 0.22, 0.14)
let top = rgb(0.93, 0.91, 0.85)
let leggings = rgb(0.467, 0.502, 0.231)   // Theme.accentSoft
let leggingsShade = rgb(0.40, 0.43, 0.19)

// MARK: - Keyframes

struct Track {
    var keys: [(Double, Double)]
    func callAsFunction(_ t: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for i in 1..<keys.count where t < keys[i].0 {
            let (t0, v0) = keys[i - 1], (t1, v1) = keys[i]
            let u = (t - t0) / (t1 - t0)
            let e = 0.5 - 0.5 * cos(.pi * u)   // ease in-out, zero velocity at keys
            return v0 + (v1 - v0) * e
        }
        return last.1
    }
}

func smoothWindow(_ t: Double, _ a: Double, _ b: Double, ramp: Double) -> Double {
    if t <= a || t >= b { return 0 }
    let up = min(1, (t - a) / ramp), down = min(1, (b - t) / ramp)
    let x = min(up, down)
    return x * x * (3 - 2 * x)
}

// Arm angles in degrees. `a` = upper arm from hanging straight down, positive
// swinging outward and up. `b` = elbow bend, positive folding the forearm in
// toward the midline.
let raise: [(Double, Double)] = [
    (0, 8), (6, 8), (10, 166), (14, 8), (18, 166), (22, 8), (26, 166), (30, 8),
    (32.5, 168), (41.6, 168), (43.1, 12), (50, 12),
]
let bend: [(Double, Double)] = [
    (0, 10), (6, 10), (10, 16), (14, 10), (18, 16), (22, 10), (26, 16), (30, 10),
    (32.5, 14), (41.6, 14), (43.1, 12), (50, 12),
]
// Settle: one hand to the heart, the other to the belly.
let armAL = Track(keys: raise + [(52.2, 24), (60, 24)])
let armBL = Track(keys: bend + [(52.2, 128), (60, 128)])
let armAR = Track(keys: raise + [(52.2, 12), (60, 12)])
let armBR = Track(keys: bend + [(52.2, 86), (60, 86)])
// Side sway: positive leans toward the viewer's right.
let lean = Track(keys: [(0, 0), (32.5, 0), (35.3, -15), (36.3, -15), (37.5, 0),
                        (39.7, 15), (40.7, 15), (41.9, 0)])

struct Pose {
    var aL, bL, aR, bR: Double
    var lean: Double
    var drop: Double
    var hipShift: Double
    var headTilt: Double
    var breathLift: Double
    var sway: Double
}

func pose(at t: Double) -> Pose {
    var p = Pose(aL: armAL(t), bL: armBL(t), aR: armAR(t), bR: armBR(t),
                 lean: lean(t), drop: 0, hipShift: 0, headTilt: 0, breathLift: 0, sway: 0)
    // Shake out: bounce through the knees, arms loose and jiggling.
    let shake = smoothWindow(t, 42.8, 49.8, ramp: 0.7)
    p.drop = shake * 0.02 * (0.5 - 0.5 * cos(2 * .pi * 2.0 * t))
    p.aL += shake * 7 * sin(2 * .pi * 4.0 * t)
    p.aR += shake * 7 * sin(2 * .pi * 4.0 * t + 2.1)
    p.bL += shake * 12 * sin(2 * .pi * 4.0 * t + 1.3)
    p.bR += shake * 12 * sin(2 * .pi * 4.0 * t + 3.4)
    p.headTilt = p.lean * 0.45 + shake * 2.5 * sin(2 * .pi * 2.0 * t + 0.6)
    // The hips counter the lean a touch, the way a body keeps its balance.
    p.hipShift = -p.lean / 15 * 0.014
    // Breath: in time with the arms during the reaches, a slow 5s tide elsewhere.
    let reaching = smoothWindow(t, 6, 30, ramp: 0.5)
    let tide = 0.5 - 0.5 * cos(2 * .pi * t / 5)
    let withArms = max(0, min(1, (armAL(t) - 8) / 158))
    p.breathLift = 0.006 * ((1 - reaching) * tide + reaching * withArms)
    p.sway = 0.004 * sin(2 * .pi * 0.13 * t)
    return p
}

// MARK: - Geometry

struct V { var x: Double; var y: Double }
func + (a: V, b: V) -> V { V(x: a.x + b.x, y: a.y + b.y) }
func - (a: V, b: V) -> V { V(x: a.x - b.x, y: a.y - b.y) }
func * (a: V, k: Double) -> V { V(x: a.x * k, y: a.y * k) }
func len(_ a: V) -> Double { (a.x * a.x + a.y * a.y).squareRoot() }
func rot(_ a: V, _ deg: Double, about c: V) -> V {
    let r = deg * .pi / 180, d = a - c
    return c + V(x: d.x * cos(r) - d.y * sin(r), y: d.x * sin(r) + d.y * cos(r))
}
func deg(_ d: Double) -> Double { d * .pi / 180 }

/// Figure units (1.0 = crown height, y up, origin on the floor between the
/// feet) → pixels.
let unit = 700.0
let floorY = 1280.0 * 0.235
func px(_ v: V) -> CGPoint { CGPoint(x: 360 + v.x * unit, y: floorY + v.y * unit) }

func fillCircle(_ c: CGContext, _ p: V, _ r: Double, _ color: CGColor) {
    let q = px(p), rr = r * unit
    c.setFillColor(color)
    c.fillEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr))
}

/// A limb: the hull of two circles, so it tapers from `r1` to `r2`.
func limb(_ c: CGContext, _ p: V, _ r1: Double, _ q: V, _ r2: Double, _ color: CGColor) {
    let d = len(q - p)
    guard d > 1e-6 else { fillCircle(c, p, max(r1, r2), color); return }
    let u = (q - p) * (1 / d), n = V(x: -u.y, y: u.x)
    let s = (r1 - r2) / d, k = (1 - s * s).squareRoot()
    let m1 = n * k - u * s, m2 = n * (-k) - u * s
    let path = CGMutablePath()
    path.move(to: px(p + m1 * r1))
    path.addLine(to: px(q + m1 * r2))
    path.addLine(to: px(q + m2 * r2))
    path.addLine(to: px(p + m2 * r1))
    path.closeSubpath()
    c.setFillColor(color)
    c.addPath(path)
    c.fillPath()
    fillCircle(c, p, r1, color)
    fillCircle(c, q, r2, color)
}

/// Closed Catmull-Rom spline through `pts`, as Béziers.
func smoothPath(_ pts: [V]) -> CGMutablePath {
    let path = CGMutablePath()
    let n = pts.count
    path.move(to: px(pts[0]))
    for i in 0..<n {
        let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
        let c1 = p1 + (p2 - p0) * (1.0 / 6), c2 = p2 - (p3 - p1) * (1.0 / 6)
        path.addCurve(to: px(p2), control1: px(c1), control2: px(c2))
    }
    path.closeSubpath()
    return path
}

/// Two-bone IK for a leg; the knee bends outward, as it does in a soft stance.
func knee(hip: V, ankle: V, thigh: Double, shin: Double, outward: Double) -> V {
    let d = min(len(ankle - hip), thigh + shin - 1e-4)
    let u = (ankle - hip) * (1 / len(ankle - hip))
    let cosA = (thigh * thigh + d * d - shin * shin) / (2 * thigh * d)
    let a = acos(max(-1, min(1, cosA))) * 180 / .pi
    let k1 = hip + rot(u, a, about: V(x: 0, y: 0)) * thigh
    let k2 = hip + rot(u, -a, about: V(x: 0, y: 0)) * thigh
    return (k1.x * outward > k2.x * outward) ? k1 : k2
}

// MARK: - Figure

func drawFigure(_ c: CGContext, _ p: Pose) {
    let base = V(x: p.sway, y: 0)
    let pelvis = base + V(x: p.hipShift, y: 0.52 - p.drop)
    let pivot = pelvis + V(x: 0, y: 0.06)             // the upper body bends here
    let lift = V(x: 0, y: p.breathLift)
    func upper(_ v: V) -> V { rot(v + lift, -p.lean, about: pivot) }

    // Floor shadow + a soft pool of light under the feet.
    c.saveGState()
    let spot = px(V(x: 0, y: 0.01))
    c.translateBy(x: spot.x, y: spot.y)
    c.scaleBy(x: 1, y: 0.13)
    c.drawRadialGradient(
        CGGradient(colorsSpace: nil, colors: [rgb(0.30, 0.32, 0.12, 0.40), rgb(0.30, 0.32, 0.12, 0)] as CFArray,
                   locations: [0, 1])!,
        startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 0.42 * unit, options: [])
    c.drawRadialGradient(
        CGGradient(colorsSpace: nil, colors: [rgb(0, 0, 0, 0.55), rgb(0, 0, 0, 0)] as CFArray,
                   locations: [0, 1])!,
        startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 0.17 * unit, options: [])
    c.restoreGState()

    // Legs.
    for side in [-1.0, 1.0] {
        let hip = pelvis + V(x: side * 0.044, y: -0.03)
        let ankle = V(x: side * 0.06, y: 0.05)
        let k = knee(hip: hip, ankle: ankle, thigh: 0.218, shin: 0.2235, outward: side)
        // Foot, toes turned slightly out.
        c.saveGState()
        let f = px(ankle + V(x: side * 0.018, y: -0.028))
        c.translateBy(x: f.x, y: f.y)
        c.rotate(by: side * deg(-12))
        c.setFillColor(skin)
        c.fillEllipse(in: CGRect(x: -0.036 * unit, y: -0.017 * unit, width: 0.072 * unit, height: 0.034 * unit))
        c.restoreGState()
        limb(c, k, 0.029, ankle, 0.019, leggings)
        limb(c, hip, 0.046, k, 0.030, leggings)
    }

    // Neck (under the neckline).
    limb(c, upper(V(x: 0, y: 0.79) + base), 0.019, upper(V(x: 0, y: 0.86) + base), 0.018, skinShade)

    // Chest: a tank top.
    let chest: [V] = [
        V(x: 0, y: 0.814), V(x: -0.045, y: 0.81), V(x: -0.096, y: 0.795), V(x: -0.09, y: 0.738),
        V(x: -0.078, y: 0.70), V(x: -0.060, y: 0.645), V(x: -0.066, y: 0.585), V(x: 0, y: 0.57),
        V(x: 0.066, y: 0.585), V(x: 0.060, y: 0.645), V(x: 0.078, y: 0.70), V(x: 0.09, y: 0.738),
        V(x: 0.096, y: 0.795), V(x: 0.045, y: 0.81),
    ].map { upper($0 + base + V(x: p.hipShift, y: -p.drop)) }
    c.setFillColor(top)
    c.addPath(smoothPath(chest))
    c.fillPath()

    // Hips: high-waisted leggings, drawn over the hem of the top.
    let hips: [V] = [
        V(x: -0.061, y: 0.63), V(x: -0.078, y: 0.575), V(x: -0.089, y: 0.51), V(x: -0.07, y: 0.455),
        V(x: 0, y: 0.44), V(x: 0.07, y: 0.455), V(x: 0.089, y: 0.51), V(x: 0.078, y: 0.575),
        V(x: 0.061, y: 0.63), V(x: 0, y: 0.636),
    ].map { $0 + base + V(x: p.hipShift, y: -p.drop) }
    c.setFillColor(leggings)
    c.addPath(smoothPath(hips))
    c.fillPath()

    // Head: bun, hair, face. Faceless on purpose — it's a placeholder guide.
    let neckTop = upper(V(x: 0, y: 0.86) + base)
    func head(_ v: V) -> V { rot(upper(v + base), -p.headTilt, about: neckTop) }
    fillCircle(c, head(V(x: 0, y: 0.978)), 0.031, hair)
    c.saveGState()
    let hc = px(head(V(x: 0, y: 0.908)))
    c.translateBy(x: hc.x, y: hc.y)
    c.rotate(by: deg(-(p.lean + p.headTilt)))
    c.setFillColor(hair)
    c.fillEllipse(in: CGRect(x: -0.054 * unit, y: -0.060 * unit, width: 0.108 * unit, height: 0.122 * unit))
    c.setFillColor(skin)
    c.fillEllipse(in: CGRect(x: -0.046 * unit, y: -0.064 * unit, width: 0.092 * unit, height: 0.108 * unit))
    c.restoreGState()

    // Arms, on top so a hand can rest on the chest.
    for (side, a, b) in [(-1.0, p.aL, p.bL), (1.0, p.aR, p.bR)] {
        let shoulder = V(x: side * 0.08, y: 0.78) + base + V(x: p.hipShift, y: -p.drop)
        let up = V(x: side * sin(deg(a)), y: -cos(deg(a)))
        let elbow = shoulder + up * 0.158
        let cAng = a - b
        let fore = V(x: side * sin(deg(cAng)), y: -cos(deg(cAng)))
        let wrist = elbow + fore * 0.14
        let hand = wrist + fore * 0.016
        limb(c, upper(elbow), 0.02, upper(wrist), 0.015, skinShade)
        limb(c, upper(wrist), 0.017, upper(hand + fore * 0.012), 0.014, skinShade)
        limb(c, upper(shoulder), 0.027, upper(elbow), 0.021, skin)
    }
}

// MARK: - Captions

struct Caption { let from: Double, to: Double, eyebrow: String, text: String }
let captions: [Caption] = [
    .init(from: 0.4, to: 5.8, eyebrow: "ARRIVE", text: "Stand tall,\nfeet hip-width apart"),
    .init(from: 6, to: 10, eyebrow: "01 · BREATH & REACH", text: "Inhale — arms float up"),
    .init(from: 10, to: 14, eyebrow: "01 · BREATH & REACH", text: "Exhale — let them fall"),
    .init(from: 14, to: 18, eyebrow: "01 · BREATH & REACH", text: "Inhale — reach"),
    .init(from: 18, to: 22, eyebrow: "01 · BREATH & REACH", text: "Exhale — soften"),
    .init(from: 22, to: 26, eyebrow: "01 · BREATH & REACH", text: "Once more — inhale"),
    .init(from: 26, to: 30, eyebrow: "01 · BREATH & REACH", text: "And exhale"),
    .init(from: 30, to: 32.6, eyebrow: "02 · SIDE SWAY", text: "Reach up"),
    .init(from: 32.6, to: 36.8, eyebrow: "02 · SIDE SWAY", text: "Sway to one side"),
    .init(from: 36.8, to: 42.2, eyebrow: "02 · SIDE SWAY", text: "And the other"),
    .init(from: 42.2, to: 50, eyebrow: "03 · SHAKE OUT", text: "Bounce through the knees,\narms loose"),
    .init(from: 50, to: 54.6, eyebrow: "04 · SETTLE", text: "One hand on the heart,\none on the belly"),
    .init(from: 54.6, to: 59.2, eyebrow: "04 · SETTLE", text: "Breathe.\nNotice how you feel."),
]

func font(_ name: String, _ size: CGFloat) -> CTFont { CTFontCreateWithName(name as CFString, size, nil) }

func drawLines(_ c: CGContext, _ text: String, font f: CTFont, color: CGColor, tracking: CGFloat,
               topY: CGFloat, lineHeight: CGFloat, alpha: CGFloat) {
    for (i, s) in text.components(separatedBy: "\n").enumerated() {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.copy(alpha: color.alpha * alpha)!,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        c.textPosition = CGPoint(x: (CGFloat(W) - CGFloat(w)) / 2, y: topY - CGFloat(i) * lineHeight)
        CTLineDraw(line, c)
    }
}

func drawCaption(_ c: CGContext, t: Double) {
    for cap in captions where t > cap.from - 0.01 && t < cap.to {
        // Only the cue text crossfades within a section; the eyebrow holds.
        let fade = 0.45
        let a = CGFloat(min(1, (t - cap.from) / fade, (cap.to - t) / fade))
        let prevSame = captions.contains { $0.to == cap.from && $0.eyebrow == cap.eyebrow }
        let nextSame = captions.contains { $0.from == cap.to && $0.eyebrow == cap.eyebrow }
        var ea = a
        if prevSame && t - cap.from < fade { ea = 1 }
        if nextSame && cap.to - t < fade { ea = 1 }
        drawLines(c, cap.eyebrow, font: font("Geist-Medium", 19), color: inkSoft, tracking: 4.2,
                  topY: 222, lineHeight: 0, alpha: ea * 0.9)
        drawLines(c, cap.text, font: font("Geist-Light", 38), color: ink, tracking: -0.4,
                  topY: 168, lineHeight: 46, alpha: a)
    }
}

// MARK: - Frame

func drawFrame(_ c: CGContext, t: Double) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    c.drawLinearGradient(CGGradient(colorsSpace: space, colors: [bgBottom, bgTop] as CFArray, locations: [0, 1])!,
                         start: .zero, end: CGPoint(x: 0, y: H), options: [])
    // Warm olive glow behind the figure, breathing very slowly.
    let g = px(V(x: 0, y: 0.66))
    let breathe = 1 + 0.04 * sin(2 * .pi * t / 8)
    c.drawRadialGradient(CGGradient(colorsSpace: space, colors: [glow, glow.copy(alpha: 0)!] as CFArray,
                                    locations: [0, 1])!,
                         startCenter: g, startRadius: 0, endCenter: g, endRadius: 0.62 * unit * breathe, options: [])

    drawFigure(c, pose(at: t))
    drawCaption(c, t: t)

    // Fade up from and back down to the canvas.
    let edge = min(1, t / 0.9, (DURATION - t) / 1.2)
    if edge < 1 {
        c.setFillColor(bgBottom.copy(alpha: CGFloat(1 - max(0, edge)))!)
        c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    }
}

func registerFonts(_ dir: String) {
    for name in ["Geist-Light", "Geist-Medium"] {
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).otf") as CFURL
        CTFontManagerRegisterFontsForURL(url, .process, nil)
    }
}

// MARK: - Commands

func render(fonts: String, out: String) throws {
    registerFonts(fonts)
    let url = URL(fileURLWithPath: out)
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: W, AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 1_400_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoExpectedSourceFrameRateKey: FPS,
        ] as [String: Any],
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "render", code: 1) }
    writer.startSession(atSourceTime: .zero)

    let frames = Int(DURATION * Double(FPS))
    for i in 0..<frames {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        guard let buffer = pb else { throw NSError(domain: "render", code: 2) }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: W, height: H, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setShouldAntialias(true)
        drawFrame(ctx, t: Double(i) / Double(FPS))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: FPS))
        if i % 300 == 0 { print("frame \(i)/\(frames)") }
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    if writer.status != .completed { throw writer.error ?? NSError(domain: "render", code: 3) }
}

func still(fonts: String, t: Double, out: String) throws {
    registerFonts(fonts)
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawFrame(ctx, t: t)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

func export(_ asset: AVAsset, preset: String, to out: String, as type: AVFileType) async throws {
    let url = URL(fileURLWithPath: out)
    try? FileManager.default.removeItem(at: url)
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
        throw NSError(domain: "export", code: 1)
    }
    session.shouldOptimizeForNetworkUse = true
    try await session.export(to: url, as: type)
}

func mux(video: String, audio: String, out: String) async throws {
    let v = AVURLAsset(url: URL(fileURLWithPath: video)), a = AVURLAsset(url: URL(fileURLWithPath: audio))
    let comp = AVMutableComposition()
    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: DURATION, preferredTimescale: 600))
    let vt = try await v.loadTracks(withMediaType: .video)[0]
    let at = try await a.loadTracks(withMediaType: .audio)[0]
    try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(range, of: vt, at: .zero)
    try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(range, of: at, at: .zero)
    try await export(comp, preset: AVAssetExportPresetPassthrough, to: out, as: .mp4)
}

let args = CommandLine.arguments
switch args[1] {
case "render": try render(fonts: args[2], out: args[3])
case "frame": try still(fonts: args[2], t: Double(args[3])!, out: args[4])
case "mux": try await mux(video: args[2], audio: args[3], out: args[4])
case "optimize":
    try await export(AVURLAsset(url: URL(fileURLWithPath: args[2])), preset: AVAssetExportPresetPassthrough,
                     to: args[3], as: .m4a)
case "probe":
    for file in args.dropFirst(2) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: file))
        let d = try await asset.load(.duration).seconds
        var desc: [String] = []
        for tr in try await asset.load(.tracks) {
            let size = try await tr.load(.naturalSize)
            let rate = try await tr.load(.estimatedDataRate)
            let fmts = try await tr.load(.formatDescriptions)
            let sub = fmts.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
            let fourcc = String(bytes: [24, 16, 8, 0].map { UInt8((sub >> $0) & 0xff) }, encoding: .ascii) ?? "?"
            desc.append("\(tr.mediaType.rawValue):\(fourcc) \(Int(size.width))x\(Int(size.height)) \(Int(rate / 1000))kbps")
        }
        let playable = try await asset.load(.isPlayable)
        print("\((file as NSString).lastPathComponent): \(String(format: "%.3f", d))s playable=\(playable) \(desc.joined(separator: ", "))")
    }
case "grab":
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: args[2])))
    gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
    let (img, _) = try await gen.image(at: CMTime(seconds: Double(args[3])!, preferredTimescale: 600))
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[4]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
default: fatalError("unknown command")
}
