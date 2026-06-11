//
//  ArtworkTones.swift
//  Soulfull Gatherings
//
//  Derives a (top, mid, base) tone triple from an artwork's average color,
//  so the player's aurora is graded to whatever is playing — Sedona reds
//  drift behind a desert session, Kyoto vermilion behind a temple sit.
//

import SwiftUI
import UIKit
import CoreImage

enum ArtworkTones {

    /// Average the artwork down to one color and spread it into the three
    /// aurora stops (dark floor / body / lifted glow). Returns nil when the
    /// asset is missing — callers fall back to the brand olive.
    static func extract(from imageName: String) -> (top: Color, mid: Color, base: Color)? {
        guard let uiImage = UIImage(named: imageName),
              let ciImage = CIImage(image: uiImage) else { return nil }

        let extent = ciImage.extent
        guard !extent.isEmpty else { return nil }

        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let output = filter?.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: nil)

        let r = Double(pixel[0]) / 255
        let g = Double(pixel[1]) / 255
        let b = Double(pixel[2]) / 255

        func scaled(_ factor: Double, lift: Double = 0) -> Color {
            Color(red: min(1, r * factor + lift),
                  green: min(1, g * factor + lift),
                  blue: min(1, b * factor + lift))
        }

        return (top: scaled(0.95, lift: 0.08),   // lifted glow
                mid: scaled(0.55),               // body
                base: scaled(0.22))              // dark floor
    }
}
