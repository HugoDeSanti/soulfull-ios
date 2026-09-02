//
//  make-app-icon.swift
//  Soulfull Gatherings
//
//  Regenerates the 1024×1024 App Store icon from the brand mark, so the icon is
//  reproducible rather than a binary someone once exported by hand.
//
//  Composition notes (these were measured, not guessed):
//  • `soulfull-logo-white.png` is 1825×1824 with the mark occupying only a
//    430×843 island of ink. The script finds those bounds itself, so source
//    padding never shrinks the mark.
//  • Only the top 63% of that island — the "SOUL" block — is used. The "full"
//    script beneath it is hairline (4–20px of ink per row against SOUL's
//    42–258) and turns to mush below ~120px. The home screen prints the word
//    "Soulfull" under the icon anyway, so the monogram carries it.
//  • The ground is `Theme.splash`, the same amber→sage→coal diagonal the
//    Welcome screen uses, so the icon and the first launch frame are one surface.
//
//  Output is opaque RGB with no alpha channel, as App Store Connect requires.
//
//  usage:  swift scripts/make-app-icon.swift
//          swift scripts/make-app-icon.swift <logo.png> <out.png>
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let defaultLogo = "SoulfullGatherings/Assets.xcassets/soulfull-logo-white.imageset/soulfull-logo-white.png"
let defaultOut = "SoulfullGatherings/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let args = CommandLine.arguments
let logoPath = args.count > 1 ? args[1] : defaultLogo
let outPath = args.count > 2 ? args[2] : defaultOut

/// Fraction of the mark's ink height to keep, measured from the top.
/// 0.63 ends just below the "L" and above the "full" script.
let markTopFraction: CGFloat = 0.63
/// The mark's long edge as a fraction of the canvas.
let markFill: CGFloat = 0.66

let cs = CGColorSpaceCreateDeviceRGB()

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: logoPath) as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("could not read \(logoPath)\n".data(using: .utf8)!)
    exit(1)
}

/// The bounding box of pixels with meaningful alpha — the mark's real extent.
func inkBounds(_ image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return CGRect(x: 0, y: 0, width: w, height: h) }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where px[(y * w + x) * 4 + 3] > 8 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return CGRect(x: 0, y: 0, width: w, height: h) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let ink = inkBounds(logo)

let side = 1024
guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high

// Ground — Theme.splash, widened slightly so the diagonal reads as depth
// rather than flat olive at icon scale.
let splash: [CGFloat] = [
    0.345, 0.369, 0.129, 1,   // lifted amber-sage, top-leading
    0.244, 0.263, 0.082, 1,   // Theme.accent
    0.129, 0.145, 0.047, 1,   // deepened coal, bottom-trailing
]
if let g = CGGradient(colorSpace: cs, colorComponents: splash, locations: [0, 0.52, 1], count: 3) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
}

// A warm bloom behind the mark, echoing the logo's glow on the Welcome splash.
let bloom: [CGFloat] = [0.42, 0.36, 0.15, 0.30, 0.244, 0.263, 0.082, 0.0]
if let g = CGGradient(colorSpace: cs, colorComponents: bloom, locations: [0, 1], count: 2) {
    let c = CGPoint(x: CGFloat(side) * 0.5, y: CGFloat(side) * 0.52)
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0,
                           endCenter: c, endRadius: CGFloat(side) * 0.62, options: [])
}

// The mark. CGImage origin is top-left, so cropping height from `ink.minY`
// keeps the top of the wordmark and drops the "full" script.
let box = CGRect(x: ink.minX, y: ink.minY, width: ink.width, height: ink.height * markTopFraction)
guard let mark = logo.cropping(to: box) else { exit(1) }

let scale = (CGFloat(side) * markFill) / max(box.width, box.height)
let dw = box.width * scale, dh = box.height * scale
let rect = CGRect(x: (CGFloat(side) - dw) / 2, y: (CGFloat(side) - dh) / 2, width: dw, height: dh)

ctx.setShadow(offset: .zero, blur: CGFloat(side) * 0.045,
              color: CGColor(colorSpace: cs, components: [1, 1, 1, 0.12])!)
ctx.draw(mark, in: rect)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }

print("mark ink \(Int(ink.width))×\(Int(ink.height)) → icon \(image.width)×\(image.height) at \(outPath)")
