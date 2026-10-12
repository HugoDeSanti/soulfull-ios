//
//  Retreat.swift
//  Soulfull Gatherings
//
//  In-person retreats: the catalog row, its brochure, and a member's
//  booking.
//

import SwiftUI

// MARK: - Bookings (retreat reservations / payments)

/// A retreat reservation paid through Stripe. Written server-side by the
/// `stripe-webhook` Edge Function; the app only ever reads its own rows
/// (`SupabaseService.fetchBooking`). Never construct/persist these client-side.
struct Booking: Identifiable, Hashable {
    let id: UUID
    let retreatId: Int
    /// The charge in Stripe's **minor unit** (cents), which is what Stripe
    /// reports. This was `amountUsd` in whole dollars, and the webhook's
    /// `Math.round(amount_received / 100)` rounded the cents away — a booking
    /// for $2,449.50 was recorded as $2,450. See 0009_integrity_hardening.sql.
    let amountCents: Int
    let currency: String
    /// `pending` | `paid` | `failed` | `refunded` (authoritative from Stripe).
    let status: String
    let createdAt: Date

    var isPaid: Bool { status == "paid" }

    /// Display string in the booking's own currency, cents included.
    var amountFormatted: String {
        (Decimal(amountCents) / 100).formatted(.currency(code: currency.uppercased()))
    }
}

// MARK: - Retreats (in-person)

struct Retreat: Identifiable, Hashable {
    let id: Int
    let name: String
    let country: String
    let startDate: Date
    let endDate: Date
    let maxGuests: Int
    let priceUsd: Int
    let tags: [String]
    let blurb: String
    /// Asset catalog name (current) or Supabase Storage URL (future).
    let imageUrl: String
    /// Visual tone sourced from the DB; used for backdrop color grading.
    let toneTop: Color
    let toneMid: Color
    let toneBase: Color
    /// External cohort group-chat link (a WhatsApp invite), sourced from the DB
    /// `retreats.group_chat_url` column and surfaced in the post-purchase hub —
    /// so adding a retreat's chat link is a data change, not an app release.
    /// `nil` → no group-chat tile. Defaulted `var` so the memberwise init stays
    /// compatible with the DB row mapper and the mock.
    var groupChatURL: URL? = nil
    /// Optional long-form editorial content for the detail screen. When set,
    /// `RetreatDetailView` renders the full spread (invitation, who it's for,
    /// the four elements, a member's word, guides, stay & inclusions); when
    /// nil it falls back to the concise tag-based layout. Mock-only for now —
    /// not yet sourced from Supabase, so `RetreatRow` leaves it at the default.
    /// Must stay a defaulted `var` so the synthesized memberwise init keeps it
    /// optional for the DB call site.
    var experience: RetreatExperience? = nil

    var tone: (top: Color, mid: Color, base: Color) { (toneTop, toneMid, toneBase) }

    /// Formatted date range for display, e.g. "April 18–23" or "Jan 10–Feb 3".
    var when: String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if cal.component(.month, from: startDate) == cal.component(.month, from: endDate) {
            fmt.dateFormat = "MMMM d"
            let start = fmt.string(from: startDate)
            fmt.dateFormat = "d"
            return "\(start)–\(fmt.string(from: endDate))"
        } else {
            fmt.dateFormat = "MMM d"
            return "\(fmt.string(from: startDate))–\(fmt.string(from: endDate))"
        }
    }

    var durationDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    var priceFormatted: String {
        priceUsd.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Retreat, rhs: Retreat) -> Bool { lhs.id == rhs.id }
}

// MARK: - Rich retreat experience (editorial detail content)

/// Long-form content that turns a retreat's detail screen into a full
/// editorial spread. All copy is curated from the retreat's own brochure;
/// the goal is to inspire, not to exhaustively list. Value type, `Hashable`
/// so it slots cleanly into the `Retreat` value (whose own `==`/`hash` stay
/// id-only).
struct RetreatExperience: Hashable, Codable {
    /// Kind line above the title on the cover (e.g. "A Wellness & Fitness Retreat").
    let kind: String
    /// Brochure date line for the cover (e.g. "July 21–26"), overriding the
    /// row's real dates.
    ///
    /// **Optional, and normally leave it out.** When it's absent the screen
    /// derives the line from `start_date`/`end_date`, which cannot drift. A
    /// hardcoded "July 21–26" sitting on top of a row that says 2027-07-21 is
    /// two sources of truth for one fact, and they have already disagreed once.
    /// Set it only when the brochure genuinely says something the dates don't
    /// ("Midsummer week"), and then remember it wins.
    var dateRange: String? = nil
    /// One-line invitation shown under the cover title.
    let coverLine: String
    /// The opening invitation — one short stanza per paragraph.
    let invitation: [String]
    /// "Who this is for" lines.
    let whoFor: [String]
    /// The closing welcome under "who this is for".
    let welcome: String
    /// The four elements every day is built from.
    let elements: [Element]
    /// A member's testimonial, if any.
    let testimonial: Testimonial?
    /// The small team leading the week.
    let guides: [Guide]
    /// Stay description (villa, room options).
    let stay: String
    /// What's included.
    let inclusions: [String]
    /// Fine print (e.g. what isn't included).
    let inclusionsNote: String?
    /// Content unlocked once the retreat is reserved — the post-purchase
    /// experience (welcome hub, to-do's, packing, 1:1 guide sessions, mocked
    /// trip logistics). Mirrors the Claude Design `mallorca-*` / `retreat-*` screens.
    /// `nil` for retreats without a curated trip. Must stay a defaulted `var`
    /// (not `let`) so the synthesized memberwise init still accepts it — a
    /// `let` with a default is omitted from the memberwise initializer.
    var postBooking: PostBooking? = nil

    /// Move / Explore / Recover / Connect — title, icon, a line, a few specifics.
    struct Element: Hashable, Identifiable, Codable {
        var id: String { title }
        let title: String
        let systemImage: String
        let summary: String
        let highlights: [String]
    }

    struct Testimonial: Hashable, Codable {
        let quote: String
        let author: String
        /// e.g. "Entrepreneur, 29 · Member since 2023".
        let attribution: String
    }

    struct Guide: Hashable, Identifiable, Codable {
        var id: String { name }
        let name: String
        let role: String

        /// Up to two initials for the avatar.
        var initials: String {
            name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
        }
    }

    /// The post-purchase trip: everything unlocked after a retreat is reserved.
    /// All copy is curated brochure content; bookable/checkable state is kept
    /// device-locally by `RetreatTripStore` (no backend yet).
    struct PostBooking: Hashable, Codable {
        /// Member display name used in greetings — a mock fallback; views should
        /// prefer the signed-in profile/`AppSettings` name when available.
        let memberName: String
        /// Reserve / checkout review content (presentational; the live charge
        /// still goes through the single-payment Stripe flow).
        let checkout: Checkout
        /// Pre-retreat checklist (completion persisted by `RetreatTripStore`).
        let todos: [TodoItem]
        /// Packing-list lines.
        let packing: [String]
        /// Bookable 1:1 sessions, each tied to a `guides` entry by name.
        let offers: [GuideOffer]

        // MARK: Trip photography
        //
        // These were hardcoded `Image("mb-welcome")` / `("mb-villa")` etc. in
        // the four trip screens — "mb" for *Mallorca brochure*. That is fine
        // while Mallorca is the only trip with content and wrong the moment it
        // isn't: reserve Patagonia and the packing screen shows a Mallorca
        // villa, confidently, with nothing to suggest anything is off.
        //
        // `bucket/path.jpg` like every other catalog image. All optional — a
        // trip with no photography renders its palette alone, which is a
        // deliberate blank rather than someone else's holiday.
        let welcomeImage: String?
        let featuredTodoImage: String?
        let todosImage: String?
        let packingImage: String?
        let guidesImage: String?

        struct Checkout: Hashable, Codable {
            let lineItems: [LineItem]
            let total: String
            /// Amount due at reserve (e.g. the deposit) and a one-line note.
            let dueToday: String
            let dueTodayNote: String
            let receiptNumber: String
            let fineprint: String

            struct LineItem: Hashable, Identifiable, Codable {
                var id: String { title }
                let title: String
                let detail: String
                let value: String
            }
        }

        struct TodoItem: Hashable, Identifiable, Codable {
            let id: String
            let title: String
            let detail: String
            /// Small tag pill ("Do this first" / "Required"); `nil` for none.
            let tag: String?
            /// Whether the tag renders as a filled "must-do" pill.
            let isMust: Bool
        }

        struct GuideOffer: Hashable, Identifiable, Codable {
            /// Matches the guide's `name` in `RetreatExperience.guides`.
            var id: String { guideName }
            let guideName: String
            let session: String
            let duration: String
            let slots: [String]
        }

    }
}

extension Retreat {
    /// The retreat's last day is behind us — what the You tab needs before it
    /// calls a retreat one the member has *been on*. Compared in the device's
    /// calendar, the same one `RetreatRow` parsed the date in: this is a
    /// question about the member's own past, not about keeping a shared catalog
    /// consistent across time zones (`fetchRetreats` filters on the server's
    /// date for that).
    var hasEnded: Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: endDate) < calendar.startOfDay(for: .now)
    }

    /// "July 21–26, 2027". `when` omits the year because the catalog only ever
    /// shows the months ahead; a retreat in someone's history needs it.
    var whenWithYear: String {
        "\(when), \(Calendar.current.component(.year, from: endDate))"
    }
}
