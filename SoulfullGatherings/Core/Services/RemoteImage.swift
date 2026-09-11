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
/// Two layers, deliberately. `URLSession`'s shared `URLCache` already keeps the
/// *bytes* on disk — Supabase Storage serves public objects with cache headers
/// — so this exists to avoid re-*decoding* them, which is the expensive part
/// when the retreats stack crossfades between every photograph in the catalog
/// at once.
///
/// An actor because two views asking for the same photo in the same frame is
/// the normal case here, not the exception: `inFlight` coalesces them into one
/// download instead of racing.
actor RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        // ~40MB of decoded pixels. Retreat photography is full-bleed, so this
        // is a handful of images — enough for a catalog, not enough to matter.
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    struct LoadError: LocalizedError {
        let errorDescription: String?
    }

    func image(for url: URL) async throws -> UIImage {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return try await running.value }

        let task = Task<UIImage, Error> {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LoadError(errorDescription: "Image request failed (\(http.statusCode)).")
            }
            guard let image = UIImage(data: data) else {
                throw LoadError(errorDescription: "That file isn't a readable image.")
            }
            return image
        }
        inFlight[url] = task

        do {
            let image = try await task.value
            inFlight[url] = nil
            // Approximate decoded footprint; exact byte counts would mean
            // re-encoding, which costs more than the accuracy is worth.
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: url as NSURL, cost: cost)
            return image
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    /// Already-decoded hit, if any. Lets a view paint a cached photo on its
    /// first frame instead of flashing the placeholder for a frame.
    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }
}
