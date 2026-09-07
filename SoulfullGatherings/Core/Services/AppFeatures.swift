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
    ///
    /// ⚠️ Flipping this is **not** a one-line change. Before it can go on:
    ///   • live Stripe keys + a live webhook endpoint/secret
    ///     (supabase/functions/README.md)
    ///   • a demo account with a seeded `paid` booking for App Review
    ///   • `PostBooking` content for every reservable retreat
    ///   • `depositInstallmentsEnabled` decided — see below; the checkout must
    ///     never name an amount the server won't charge.
    static let paymentsEnabled = false

    /// Deposit + installments on the retreat checkout (a deposit due today,
    /// with the balance billed monthly).
    ///
    /// **Off, because it is not built.** The plan is `docs/PLAN-deposit-installments.md`;
    /// the server charges the retreat's full `price_usd` in one payment.
    ///
    /// This flag exists because the copy shipped ahead of the capability and
    /// reached the pay button: `RetreatCheckoutView` rendered
    /// `PostBooking.Checkout.dueToday` — the hardcoded string `"€800"` — inside
    /// the button label and the "Due today — deposit" card, while
    /// `create-payment-intent` charged ~$5,678 USD. A user would have tapped
    /// "Pay €800" and been charged the full price in another currency.
    ///
    /// While this is off, the checkout shows only what the server will actually
    /// charge. Turning it on requires the installment schedule to exist
    /// server-side (a Stripe Subscription or scheduled PaymentIntents) **and**
    /// `dueToday` to be derived from it rather than from brochure copy.
    static let depositInstallmentsEnabled = false

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
