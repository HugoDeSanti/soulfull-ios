//
//  RemoteImageDecodeTests.swift
//  SoulfullTests
//
//  How a downloaded photo is held in memory. It is decoded when it arrives,
//  not when first drawn (that was on the main thread, mid-crossfade), never
//  larger than the biggest screen needs, and the cache counts what it really
//  costs. The network and the shared cache aren't touched.
//

import Foundation
import Testing
import UIKit
@testable import SoulfullGatherings

@Suite("Remote image decoding")
struct RemoteImageDecodeTests {

    /// A JPEG of the given pixel size.
    func jpeg(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A camera original uploaded as it came would decode to tens of MB.
    @Test func aPhotoLargerThanAnyScreenNeedsIsDecodedSmaller() throws {
        let image = try #require(RemoteImageCache.decoded(jpeg(width: 4_000, height: 1_000),
                                                          maxPixelSize: 2_000))

        #expect(image.cgImage?.width == 2_000)
        #expect(image.cgImage?.height == 500)
    }

    @Test func aPhotoThatFitsIsNotEnlarged() throws {
        let image = try #require(RemoteImageCache.decoded(jpeg(width: 800, height: 600)))

        #expect(image.cgImage?.width == 800)
        #expect(image.cgImage?.height == 600)
    }

    @Test func somethingThatIsntAnImageDecodesToNothing() {
        #expect(RemoteImageCache.decoded(Data("<html>Not found</html>".utf8)) == nil)
    }

    /// The cache's limit is in bytes of decoded pixels; an estimate from the
    /// point size undercounted anything not drawn at scale 1.
    @Test func theCostIsTheDecodedBytes() throws {
        let image = try #require(RemoteImageCache.decoded(jpeg(width: 1_000, height: 500)))
        let pixels = try #require(image.cgImage)

        #expect(RemoteImageCache.cost(of: image) == pixels.bytesPerRow * pixels.height)
        #expect(RemoteImageCache.cost(of: image) >= 1_000 * 500 * 4)
    }
}
