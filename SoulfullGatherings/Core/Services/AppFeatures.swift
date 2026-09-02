//
//  AppFeatures.swift
//  Soulfull Gatherings
//
//  Ship-scope flags. These exist so v1 can go to the App Store with a smaller
//  surface than the codebase actually contains — nothing is deleted, it is
//  routed around. Flipping a flag back on is the whole change.
//

import Foundation

enum AppFeatures {

    /// Retreat reservations (Stripe checkout → post-purchase experience).
    ///
    /// **Off for v1.** The payment rail is built and verified in Stripe test
    /// mode, but shipping it in 1.0 would mean: taking the account live,
    /// supplying App Review a demo account with a seeded `bookings` row (they
    /// cannot complete a real charge), justifying Stripe over IAP in the review
    /// notes, and — the real blocker — the post-purchase experience only has
    /// curated content for Mallorca, so buying any other retreat lands on empty
    /// screens.
    ///
    /// v1 ships as a browsable catalog. When this flips to `true`, restore:
    ///   • the Reserve CTA in `RetreatDetailView`
    ///   • the `retreatCheckout` / `retreatExperience` routes in `MainTabView`
    ///   • `RetreatDetailViewModel.loadExistingBooking` on appear
    /// and make sure every reservable retreat resolves a `RetreatExperience`
    /// with a `PostBooking`, not just Mallorca.
    static let paymentsEnabled = false

    /// The Circle tab (community circles, member directory, DMs).
    ///
    /// **Off for v1.** It was a `TabPlaceholder` reading "lands here next",
    /// which is a Guideline 4.2 minimum-functionality rejection. `MainTab` omits
    /// the case entirely rather than reading this flag — `BottomNav` builds from
    /// `MainTab.allCases`, so the tab disappears from the bar automatically.
    /// This constant documents the decision; `CommunityPlaceholder` is parked,
    /// not deleted.
    static let circleTabEnabled = false
}
