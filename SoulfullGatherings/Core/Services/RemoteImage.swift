//
//  RemoteImage.swift
//  Soulfull Gatherings
//
//  Lets catalog photography come from Supabase Storage instead of the app
//  bundle, so adding a retreat is a database row and an upload rather than an
//  App Store release.
//
//  The column is called `image_url` but used to hold an **asset-catalog name**
//  ("retreat-mallorca"), rendered with `Image(_ name:)` — a bundle lookup. A
//  name that wasn't bundled drew nothing at all: no error, no placeholder, just
//  a blank photo area. So a new retreat could be inserted and look broken with
//  nothing to explain why.
//
//  `ImageSource` routes on the *shape* of the string, so both kinds coexist and
//  the existing seeded rows keep working untouched.
//

import SwiftUI
import UIKit
import ImageIO

/// Where one catalog photograph lives.
///
/// Routing, in order:
///   `https://…/photo.jpg`   → `.remote`, fetched as-is
///   `retreat-images/x.jpg`  → `.remote`, resolved to that bucket's public URL
///   `retreat-mallorca`      → `.asset`, looked up in Assets.xcassets
///
/// A storage value **must** carry its bucket as the first path segment. That
/// keeps the row self-describing — you can read where a photo lives off the
/// row itself — and means no bucket name is hardcoded in the app, so a new
/// bucket needs no release either.
enum ImageSource: Hashable, Sendable {
    case asset(String)
    case remote(URL)
    /// Shaped like a storage path but the URL couldn't be built. Renders the
    /// placeholder rather than nothing.
    case unresolved(String)

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { self = .unresolved(raw); return }

        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            self = URL(string: trimmed).map(ImageSource.remote) ?? .unresolved(trimmed)
            return
        }

        // "bucket/path/to/file.jpg" — split once; everything after the first
        // slash is the object path, which may itself contain slashes.
        if let slash = trimmed.firstIndex(of: "/") {
            let bucket = String(trimmed[trimmed.startIndex..<slash])
            let path = String(trimmed[trimmed.index(after: slash)...])
            if !bucket.isEmpty, !path.isEmpty,
               let url = SupabaseService.shared.publicObjectURL(bucket: bucket, path: path) {
                self = .remote(url)
            } else {
                self = .unresolved(trimmed)
            }
            return
        }

        self = .asset(trimmed)
    }
}

/// Decoded-image cache in front of `URLSession`.
///
/// Two layers, deliberately. `URLSession`'s shared `URLCache` holds the *bytes*
/// and Storage serves a strong `ETag`, so a repeat request revalidates and comes
/// back `304` with an empty body instead of re-downloading. What that does not
/// avoid is re-*decoding* them — the expensive part when the retreats stack
/// crossfades between every photograph in the catalog at once. That is what this
/// cache is for.
///
/// Note Supabase answers `cache-control: no-cache` on public objects **whatever
/// `cacheControl` you set at upload** (the value is kept in the object's
/// metadata for its CDN, not echoed to the client — verified 2026-09-14). So a
/// cold launch always pays one revalidation round trip per photo. That is cheap,
/// and it costs nothing offline: the catalog has no offline fallback, so there
/// are no cards to put photographs on in the first place.
///
/// An actor because two views asking for the same photo in the same frame is
/// the normal case here, not the exception: `inFlight` coalesces them into one
/// download instead of racing.
actor RemoteImageCache {
    static let shared = RemoteImageCache()

    /// `nonisolated(unsafe)` so a view can read a hit synchronously, in `body`
    /// (see `cached`). NSCache is documented as thread-safe; the actor still
    /// owns the coalescing of downloads.
    nonisolated(unsafe) private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        // Decoded pixels, counted exactly (`cost(of:)`). A catalog photo
        // (~2,000px, per the retreat runbook) is ~11MB decoded, so this holds
        // the whole catalog plus faces. It was 40MB — three photos — and the
        // retreats stack, crossfading through all of them, evicted and decoded
        // them again as it went. NSCache gives memory back under pressure.
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    struct LoadError: LocalizedError {
        let errorDescription: String?
    }

    /// The longest side, in pixels, a photograph is decoded at. Nothing on
    /// an iPhone needs more (the tallest screen is 2,868), and a camera
    /// original uploaded as it came (6,000 × 4,000) would otherwise decode
    /// to 96MB.
    static let maxPixelSize = 3_000

    func image(for url: URL) async throws -> UIImage {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return try await running.value }

        let task = Task<UIImage, Error> { try await Self.download(url) }
        inFlight[url] = task

        do {
            let image = try await task.value
            inFlight[url] = nil
            memory.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
            return image
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    /// Fetches and decodes, off the actor (a `nonisolated` async function runs
    /// on the global executor) so photos decode side by side, and off the main
    /// thread, which is the point: `UIImage(data:)` only decoded when the
    /// image was first DRAWN, on the main thread, mid-crossfade.
    private nonisolated static func download(_ url: URL) async throws -> UIImage {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoadError(errorDescription: "Image request failed (\(http.statusCode)).")
        }
        guard let image = decoded(data) else {
            throw LoadError(errorDescription: "That file isn't a readable image.")
        }
        return image
    }

    /// Decodes `data` now, on the calling thread, no larger than
    /// `maxPixelSize` on its longest side (never enlarged), upright whatever
    /// its EXIF orientation. Nil for something that isn't an image.
    nonisolated static func decoded(_ data: Data, maxPixelSize: Int = maxPixelSize) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decoded here, not lazily on first draw.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// What an image holds in memory, decoded.
    nonisolated static func cost(of image: UIImage) -> Int {
        if let pixels = image.cgImage { return pixels.bytesPerRow * pixels.height }
        return Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    }

    /// Already-decoded hit, if any. Synchronous so a view can paint a cached
    /// photo on its first frame: asked from a `.task`, the answer only arrived
    /// after the placeholder had already been drawn, so every new screen
    /// flashed the gradient before photos it already had.
    nonisolated func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Seeds the cache with an image this device made itself — a just-uploaded
    /// profile photo — so it shows at once under its new URL instead of being
    /// downloaded straight back.
    nonisolated func insert(_ image: UIImage, for url: URL) {
        memory.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
    }
}
