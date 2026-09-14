//
//  RetreatPalette.swift
//  Soulfull Gatherings
//
//  Warm-espresso palette for the Mallorca post-purchase experience — the UX
//  team's retreat-specific dark direction (terracotta / olive / gold on an
//  espresso canvas), distinct from the app-wide `Theme`. It mirrors the inline
//  `.mb` palette in the Claude Design `mallorca-*` / `retreat-*` cards
//  (design-system/screens). Only the post-purchase screens use this; the rest
//  of the app stays on `Theme`. Hex values are the single source shared with
//  the CSS mirror.
//

import SwiftUI

enum RetreatPalette {
    /// Canvas.
    static let espresso  = Color(hex: "#1a130c")
    static let espresso2 = Color(hex: "#22180e")
    static let coffee    = Color(hex: "#3a2a1c")

    /// Text.
    static let cream     = Color(hex: "#f3ead9")   // primary
    static let creamSoft = Color(hex: "#cbbca2")   // secondary
    static let muted     = Color(hex: "#94856c")   // tertiary / metadata

    /// Accents.
    static let terracotta = Color(hex: "#c47c4c")  // eyebrows, primary CTAs
    static let olive       = Color(hex: "#8d8a4c") // success / booked / checks
    static let gold        = Color(hex: "#e5c766") // highlight (== Theme.honey)

    /// Warm cream-tinted glass (vs the app's white glass).
    static let glassTint     = cream.opacity(0.05)
    static let glassLine     = cream.opacity(0.12)
    static let glassLineSoft = cream.opacity(0.08)
}

/// Header photography for a trip screen, addressed by the trip document
/// (`bucket/path.jpg`) rather than hardcoded in the view.
///
/// It used to be `Image("mb-villa")` and friends — "mb" for *Mallorca
/// brochure*. Fine while Mallorca was the only trip with content, and wrong
/// the moment it isn't: reserve Patagonia and the packing screen would show a
/// Mallorca villa, confidently, with nothing to suggest anything was off.
///
/// `nil` paints the espresso ground instead. A trip with no photography of its
/// own should look deliberately spare, never borrow someone else's holiday.
struct TripImage: View {
    let path: String?

    init(_ path: String?) { self.path = path }

    var body: some View {
        if let path, !path.trimmingCharacters(in: .whitespaces).isEmpty {
            CatalogImage(path) { $0.resizable().scaledToFill() }
        } else {
            RetreatPalette.espresso
        }
    }
}
