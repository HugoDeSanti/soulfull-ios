//
//  CatalogImage.swift
//  Soulfull Gatherings
//
//  Renders a catalog photograph from wherever it lives — the app bundle or
//  Supabase Storage — and hands the resolved `Image` back to the caller to
//  style. See `ImageSource` for the routing.
//
//  It yields the `Image` through a ViewBuilder rather than styling it here
//  because every caller treats it differently: `PhotoBackdrop` blurs,
//  saturates and pans it; the retreat cards clip it to a fixed frame; the
//  detail hero scales it. Wrapping the styling would mean reproducing all of
//  that behind a set of flags.
//

import SwiftUI

struct CatalogImage<Styled: View>: View {
    let source: ImageSource
    @ViewBuilder var style: (Image) -> Styled

    @State private var loaded: UIImage?
    @State private var failed = false

    init(_ raw: String, @ViewBuilder style: @escaping (Image) -> Styled) {
        self.source = ImageSource(raw)
        self.style = style
    }

    init(source: ImageSource, @ViewBuilder style: @escaping (Image) -> Styled) {
        self.source = source
        self.style = style
    }

    var body: some View {
        switch source {
        case .asset(let name):
            // `UIImage(named:)` first: `Image(name)` on a name that isn't in
            // the catalog renders nothing at all, silently, which is the exact
            // failure this type exists to stop.
            if let bundled = UIImage(named: name) {
                style(Image(uiImage: bundled))
            } else {
                placeholder
            }

        case .remote(let url):
            if let loaded {
                style(Image(uiImage: loaded))
                    // Crossfade rather than snap. A bundled image was simply
                    // *there* on the first frame; a fetched one cannot be, so a
                    // list of them pops in one by one as each download lands.
                    // The fade turns that into something that reads as
                    // deliberate. Opacity only — nothing moves, so this is
                    // still calm under Reduce Motion.
                    .transition(.opacity)
            } else if failed {
                placeholder
            } else {
                placeholder
                    .task(id: url) { await load(url) }
            }

        case .unresolved:
            placeholder
        }
    }

    private func load(_ url: URL) async {
        // A cache hit paints on this frame instead of flashing the placeholder,
        // and is assigned without animation: it was effectively already here,
        // so fading it in would only look like lag.
        if let hit = await RemoteImageCache.shared.cached(url) {
            loaded = hit
            return
        }
        do {
            let image = try await RemoteImageCache.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.32)) { loaded = image }
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            Log.media.error("Catalog image failed: \(error.localizedDescription)")
        }
    }

    /// Quiet, deliberately. This sits under full-bleed editorial type, so it
    /// has to read as an unlit photograph rather than a broken one — a spinner
    /// or a torn-image glyph would be louder than the content it stands in for.
    private var placeholder: some View {
        LinearGradient(
            colors: [Theme.surface, Theme.bgDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(Theme.bg.opacity(0.35))
    }
}
