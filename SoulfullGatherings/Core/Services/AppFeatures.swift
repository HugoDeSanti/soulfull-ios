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
    /// v1 ships as a browsable catalog.
    ///
    /// ⚠️ **Flipping this alone now does almost nothing.** The client payment
    /// rail was *removed*, not just routed around, when the StripePaymentSheet
    /// SPM dependency was dropped — that dependency linked a card scanner,
    /// which forced an `NSCameraUsageDescription` for a capability the app
    /// could not reach, and a purpose string with no feature behind it invites
    /// a reviewer to ask where the camera is used. Deleted with it:
    ///   • `Core/Services/PaymentService.swift`
    ///   • `Features/Retreats/PostPurchase/RetreatCheckoutView.swift`
    ///   • `RetreatDetailViewModel.reserve()` / `confirmBooking()`
    ///   • the `retreatCheckout` route in `MainTabView`
    /// All recoverable from git history. `loadExistingBooking` **stayed** —
    /// reading a `bookings` row is plain Supabase, so a reservation made by any
    /// means still shows on the detail screen.
    ///
    /// The **server** rail is untouched and still deployed: `create-payment-intent`
    /// and `stripe-webhook` are Edge Functions, not part of the app build.
    ///
    /// So bringing payments back means, in order:
    ///   • re-add the `Stripe` package + `StripePaymentSheet` product and the
    ///     camera purpose string to `project.yml`
    ///   • restore the four deleted Swift pieces from git history
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
    /// reached the pay button: the since-deleted `RetreatCheckoutView` rendered
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
