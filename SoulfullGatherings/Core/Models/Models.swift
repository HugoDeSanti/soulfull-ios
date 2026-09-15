//
//  Models.swift
//  Soulfull Gatherings
//
//  Data models. All structs are value types, Identifiable, and Hashable so
//  they slot into NavigationStack value destinations.
//

import SwiftUI

// MARK: - User profile (Supabase `profiles` table)

/// One row per authenticated user (anonymous guest or permanent account).
/// Mirrors the `profiles` table: the row is created server-side by a trigger
/// and synced from the app via `SupabaseService.upsertProfile`/`fetchProfile`.
/// `stripeCustomerId` is read-only here — it is written by the Phase 2 Stripe
/// webhook, never by the client.
struct Profile: Identifiable, Hashable {
    let id: UUID
    var email: String
    var fullName: String
    var intentions: [String]
    var bodyState: String
    var frequency: String
    var stripeCustomerId: String?
}

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
    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// True once the retreat's first day has arrived. The catalog must not
    /// offer a place on something already under way — a price and a date you
    /// can no longer act on is worse than an empty shelf.
    ///
    /// Mirrors the `start_date > today` filter in
    /// `SupabaseService.fetchRetreats()`, in UTC for the same reason: the dates
    /// are bare Postgres `date`s, so comparing in the device's zone made the
    /// catalog disagree with itself either side of the date line.
    var hasBegun: Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = utc.startOfDay(for: Date())
        return utc.startOfDay(for: startDate) <= today
    }

    /// Sample retreats, used as a graceful fallback when Supabase is
    /// unreachable (same pattern as `PracticeSession.mock`).
    ///
    /// ⚠️ These dates are absolute and **will rot**. Filter every use through
    /// `hasBegun` (`Retreat.mock.filter { !$0.hasBegun }`) so a stale fixture
    /// shows nothing rather than advertising a retreat that already happened —
    /// which is exactly what the offline fallback did until 2026-09-10.
    ///
    /// These carry **no** `experience`: the brochure lives in the
    /// `retreats.experience` jsonb column, so there is nothing to hardcode here
    /// any more. A fixture retreat therefore renders the concise layout, which
    /// is correct — an offline device has no brochure to show.
    static let mock: [Retreat] = [
        Retreat(id: 1, name: "Mallorca", country: "Spain",
                startDate: day(2027, 7, 21), endDate: day(2027, 7, 26),
                maxGuests: 14, priceUsd: 4400,
                tags: ["Wellness", "Fitness", "Recovery"],
                blurb: "A private Mediterranean villa, curated company, and days built to move, explore, recover, and connect.",
                imageUrl: "retreat-images/mallorca-2027-07.jpg",
                toneTop: Color(hex: "#73A0B8"), toneMid: Color(hex: "#335266"), toneBase: Color(hex: "#0F1A24"),
                // Offline fallback only — production reads retreats.group_chat_url from the DB.
                // No placeholder invite here: a dead chat.whatsapp.com link in
                // the offline fallback is worse than no tile, and the hub only
                // renders the tile when this is non-nil. Real invites come from
                // `retreats.group_chat_url`, so adding one is a data change.
                groupChatURL: nil),
        Retreat(id: 2, name: "Bali", country: "Indonesia",
                startDate: day(2027, 8, 9), endDate: day(2027, 8, 16),
                maxGuests: 16, priceUsd: 3900,
                tags: ["Breathwork", "Somatic", "Jungle"],
                blurb: "Seven nights between rice terraces and temple mornings. Breath, stillness, and green without end.",
                imageUrl: "retreat-images/bali-2026-07.jpg",
                toneTop: Color(hex: "#9DBA6E"), toneMid: Color(hex: "#4C6B33"), toneBase: Color(hex: "#15200D")),
        Retreat(id: 3, name: "Dolomites", country: "Italy",
                startDate: day(2027, 9, 8), endDate: day(2027, 9, 13),
                maxGuests: 12, priceUsd: 5200,
                tags: ["Alpine", "Hiking", "Cold Therapy"],
                blurb: "Granite light, long ridgelines, and evenings that ask very little of you. Walk up, settle down.",
                imageUrl: "retreat-images/dolomites-2027-09.jpg",
                toneTop: Color(hex: "#B9C3CD"), toneMid: Color(hex: "#5C6B7A"), toneBase: Color(hex: "#161B21")),
        Retreat(id: 4, name: "Kyoto", country: "Japan",
                startDate: day(2027, 10, 12), endDate: day(2027, 10, 18),
                maxGuests: 10, priceUsd: 6100,
                tags: ["Zen", "Tea", "Forest Bathing"],
                blurb: "Temple gardens at first light, tea in silence, maple shade. A week of deliberate slowness.",
                imageUrl: "retreat-images/kyoto-2026-05.jpg",
                toneTop: Color(hex: "#C98A66"), toneMid: Color(hex: "#7A4631"), toneBase: Color(hex: "#1F120C")),
        Retreat(id: 5, name: "Sedona", country: "United States",
                startDate: day(2027, 11, 6), endDate: day(2027, 11, 11),
                maxGuests: 14, priceUsd: 4800,
                tags: ["Desert", "Sound Healing", "Hiking"],
                blurb: "Red rock amphitheaters, canyon hikes, sound baths under enormous sky.",
                imageUrl: "retreat-images/sedona-2026-06.jpg",
                toneTop: Color(hex: "#D88E5E"), toneMid: Color(hex: "#8C4A2D"), toneBase: Color(hex: "#23120A")),
        Retreat(id: 6, name: "Chamonix", country: "France",
                startDate: day(2027, 1, 15), endDate: day(2027, 1, 20),
                maxGuests: 12, priceUsd: 5600,
                tags: ["Snow", "Sauna", "Breathwork"],
                blurb: "Mont Blanc out every window. Powder mornings, sauna and plunge, fireside circles.",
                imageUrl: "retreat-images/chamonix-2027-02.jpg",
                toneTop: Color(hex: "#A9C3DD"), toneMid: Color(hex: "#4F6B85"), toneBase: Color(hex: "#101822")),
        Retreat(id: 7, name: "Lapland", country: "Finland",
                startDate: day(2027, 2, 19), endDate: day(2027, 2, 24),
                maxGuests: 10, priceUsd: 5900,
                tags: ["Aurora", "Ice Bath", "Silence"],
                blurb: "Northern lights over frozen lakes. Ice, heat, and the deepest quiet you've ever heard.",
                imageUrl: "retreat-images/lapland-2027-01.jpg",
                toneTop: Color(hex: "#6FA08F"), toneMid: Color(hex: "#2E5247"), toneBase: Color(hex: "#0C1714")),
    ]
}

// MARK: - Mallorca experience content (curated from the 2026 retreat brochure)

extension RetreatExperience {

    /// The post-purchase trip content for Mallorca — curated from the brochure
    /// and the Claude Design `mallorca-*` / `retreat-*` screens. Bookable state
    /// lives device-locally in `RetreatTripStore`; the copy here is static.
}

// MARK: - Digital programs (for home carousel)

struct Program: Identifiable, Hashable {
    let id: String
    let title: String
    let lead: String
    let when: String
    let days: Int
    let imageUrl: String
}

extension Program {
    static let mock: [Program] = [
        Program(id: "cyc7",  title: "Cycling & Recovery",             lead: "Valentina Velasco", when: "June 12–19",  days: 7,  imageUrl: "retreat-images/mallorca-2027-07.jpg"),
        Program(id: "bw5",   title: "Intro to Breathwork",            lead: "Rodrigo Peán",      when: "June 24–28",  days: 5,  imageUrl: "retreat-images/bali-2026-07.jpg"),
        Program(id: "yw14",  title: "Yoga & Wellness",                lead: "Alma Guerra",        when: "July 8–21",   days: 14, imageUrl: "retreat-images/dolomites-2027-09.jpg"),
        Program(id: "hcl14", title: "Heal Yourself, Change Your Life", lead: "Michelle Campos",   when: "August 1–14", days: 14, imageUrl: "retreat-images/sedona-2026-06.jpg"),
        Program(id: "md7",   title: "Movement & Discipline",          lead: "Analu Chavez",       when: "July 14–20",  days: 7,  imageUrl: "retreat-images/kyoto-2026-05.jpg"),
    ]
}

// MARK: - Practices (on-demand audio / video library)

/// The three tracks surfaced on the Practice tab. `rawValue` matches the
/// `category` column in the `practice_sessions` Supabase table.
enum PracticeCategory: String, Identifiable, Hashable, CaseIterable {
    case somatic, breathwork, meditation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .somatic:    return "Somatic Exercises"
        case .breathwork: return "Breathwork"
        case .meditation: return "Meditation"
        }
    }

    var blurb: String {
        switch self {
        case .somatic:    return "Release what the body holds. Gentle, guided work for the nervous system."
        case .breathwork: return "Shift your state through the breath. Active and restorative patterns."
        case .meditation: return "Stillness, on demand. Guided sits for focus, sleep, and calm."
        }
    }

    var systemImage: String {
        switch self {
        case .somatic:    return "figure.mind.and.body"
        case .breathwork: return "wind"
        case .meditation: return "moon.stars"
        }
    }

    /// Backdrop asset (placeholder reuse until category art is added).
    var imageName: String {
        switch self {
        case .somatic:    return "practice-somatic"
        case .breathwork: return "practice-breathwork"
        case .meditation: return "practice-meditation"
        }
    }
}

/// Whether a session plays as audio-only or full video. Maps to the
/// `media_kind` column.
enum MediaKind: String, Hashable {
    case audio, video

    var label: String { self == .audio ? "Audio" : "Video" }
    var systemImage: String { self == .audio ? "waveform" : "play.rectangle.fill" }
}

/// A playable piece of media, decoupled from the content type that owns it, so
/// `PracticePlayerView` can serve any library that grows media.
struct MediaItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let lead: String
    let imageUrl: String
    let mediaKind: MediaKind
    /// Storage object path, or an absolute `http(s)` URL for sample / public media.
    let storagePath: String
    let durationSeconds: Int
    /// Which library this came from. The player records playback against it, so
    /// two libraries' items with the same numeric id stay distinct in the
    /// ledger that creator payouts are drawn from.
    var contentKind: PracticeContentKind = .session
    /// Media track, for sessions; `nil` for other libraries.
    var category: PracticeCategory? = nil

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }
}

struct PracticeSession: Identifiable, Hashable {
    let id: Int
    let category: PracticeCategory
    let title: String
    /// Instructor / guide.
    let lead: String
    let mediaKind: MediaKind
    /// Supabase Storage object path (e.g. "somatic/grounding-scan.m4a"), or an
    /// absolute `http(s)` URL for externally-hosted / sample media.
    let storagePath: String
    let durationSeconds: Int
    /// Asset catalog name (current) or Storage URL (future).
    let imageUrl: String
    let blurb: String

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    var media: MediaItem {
        MediaItem(id: id, title: title, lead: lead, imageUrl: imageUrl,
                  mediaKind: mediaKind, storagePath: storagePath, durationSeconds: durationSeconds,
                  contentKind: .session, category: category)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PracticeSession, rhs: PracticeSession) -> Bool { lhs.id == rhs.id }
}

extension PracticeSession {
    /// Shape-only fixtures for SwiftUI previews.
    ///
    /// These used to carry public sample media (a stock MP3 and Big Buck Bunny)
    /// and were the runtime fallback whenever `practice_sessions` was unseeded —
    /// which meant a shipping build played a cartoon rabbit as a guided
    /// meditation. `storagePath` is now empty and nothing in the app reads these
    /// at runtime: `PracticeViewModel` reports an unseeded track as empty and
    /// `PracticeView` renders it as "Coming soon".
    ///
    /// Real rows carry a bucket-relative `storagePath` resolved via a signed URL.
    static let mock: [PracticeSession] = [
        // Somatic Exercises
        .init(id: 1, category: .somatic, title: "Grounding Body Scan", lead: "Dr. Anya Iyer", mediaKind: .audio, storagePath: "", durationSeconds: 720, imageUrl: "retreat-images/sedona-2026-06.jpg", blurb: "A slow head-to-toe scan to settle the nervous system."),
        .init(id: 2, category: .somatic, title: "Shake & Release", lead: "Mara Solé", mediaKind: .audio, storagePath: "", durationSeconds: 480, imageUrl: "retreat-images/mallorca-2027-07.jpg", blurb: "Discharge held tension through gentle, guided movement."),
        .init(id: 3, category: .somatic, title: "Orienting to Safety", lead: "Theo Park", mediaKind: .video, storagePath: "", durationSeconds: 900, imageUrl: "retreat-images/dolomites-2027-09.jpg", blurb: "A trauma-informed practice for re-establishing felt safety."),

        // Breathwork
        .init(id: 4, category: .breathwork, title: "Box Breathing Basics", lead: "Rodrigo Peán", mediaKind: .audio, storagePath: "", durationSeconds: 360, imageUrl: "retreat-images/bali-2026-07.jpg", blurb: "Four-count breathing to steady a racing mind."),
        .init(id: 5, category: .breathwork, title: "Coherent Breathing", lead: "Valentina Velasco", mediaKind: .audio, storagePath: "", durationSeconds: 600, imageUrl: "retreat-images/mallorca-2027-07.jpg", blurb: "Five breaths a minute to balance the autonomic system."),
        .init(id: 6, category: .breathwork, title: "Breath of Fire", lead: "Alma Guerra", mediaKind: .video, storagePath: "", durationSeconds: 540, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "An energizing kundalini practice to wake the body."),

        // Meditation
        .init(id: 7, category: .meditation, title: "Morning Stillness", lead: "Michelle Campos", mediaKind: .audio, storagePath: "", durationSeconds: 600, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "Begin the day with ten minutes of open awareness."),
        .init(id: 8, category: .meditation, title: "Sleep Descent", lead: "Analu Chavez", mediaKind: .audio, storagePath: "", durationSeconds: 1200, imageUrl: "retreat-images/dolomites-2027-09.jpg", blurb: "A long, drifting body relaxation for falling asleep."),
        .init(id: 9, category: .meditation, title: "Loving-Kindness", lead: "Mara Solé", mediaKind: .audio, storagePath: "", durationSeconds: 840, imageUrl: "retreat-images/sedona-2026-06.jpg", blurb: "Cultivate warmth toward yourself and others."),
    ]

    static func mock(for category: PracticeCategory) -> [PracticeSession] {
        mock.filter { $0.category == category }
    }
}

// MARK: - Practice progress (what a member has played)

/// Which library a tracked practice came from. Mirrors the `content_kind`
/// column on `practice_plays`; the raw values are the contract with the DB
/// check constraint, so don't rename them casually — and if you drop one, drop
/// it from the constraint too or the schema keeps accepting a value no client
/// can produce (`massage` went both ways in 0012).
enum PracticeContentKind: String, Hashable, Codable, Sendable {
    case session, journal, exercise, recipe

    /// Whether this library credits a named creator. Sessions name a real guide
    /// who gets paid; the written libraries are house content for now, so they
    /// record a null creator and simply don't appear in a payout run until that
    /// changes.
    var creditsCreator: Bool {
        switch self {
        case .session:                      return true
        case .journal, .exercise, .recipe:  return false
        }
    }
}

/// One playback / reading session, addressed by a client-generated `eventID` so
/// heartbeats and retries land on the same ledger row instead of paying a
/// creator twice for one listen.
struct PracticePlay: Hashable, Sendable {
    let eventID: UUID
    let kind: PracticeContentKind
    let contentID: Int
    let title: String
    /// Snapshot of the creator's name at play time — deliberately copied rather
    /// than joined, so retitling or reassigning content can't move historical
    /// payouts. `nil` for the written libraries.
    let creator: String?
    let category: PracticeCategory?
    let durationSeconds: Int?

    init(kind: PracticeContentKind, contentID: Int, title: String,
         creator: String? = nil, category: PracticeCategory? = nil,
         durationSeconds: Int? = nil, eventID: UUID = UUID()) {
        self.eventID = eventID
        self.kind = kind
        self.contentID = contentID
        self.title = title
        self.creator = creator
        self.category = category
        self.durationSeconds = durationSeconds
    }

    /// Stable identity of the *content* (not the play), matching
    /// `PracticeProgress.id`.
    var contentKey: String { "\(kind.rawValue)-\(contentID)" }
}

extension PracticePlay {
    static func media(_ item: MediaItem) -> PracticePlay {
        PracticePlay(kind: item.contentKind, contentID: item.id, title: item.title,
                     creator: item.lead, category: item.category,
                     durationSeconds: item.durationSeconds)
    }

    /// A prompt has no intrinsic length, but it needs a nominal one: it is the
    /// bound the DB trigger clamps `seconds_played` against
    /// (`least(seconds_played, duration_seconds)`), and with it null the clamp
    /// is skipped entirely and a journal play accrues without limit. Fifteen
    /// minutes is a long sitting with one prompt.
    static func journal(_ prompt: JournalPrompt) -> PracticePlay {
        PracticePlay(kind: .journal, contentID: prompt.id, title: prompt.title,
                     durationSeconds: 900)
    }

    static func exercise(_ exercise: Exercise) -> PracticePlay {
        PracticePlay(kind: .exercise, contentID: exercise.id, title: exercise.title,
                     durationSeconds: exercise.durationSeconds)
    }

    /// `Recipe.lead` is a dietary angle ("Anti-inflammatory"), not a person, so
    /// it is deliberately NOT passed as the creator — a payout run must never
    /// try to pay "Gut-friendly".
    static func recipe(_ recipe: Recipe) -> PracticePlay {
        PracticePlay(kind: .recipe, contentID: recipe.id, title: recipe.title,
                     durationSeconds: recipe.minutes * 60)
    }
}

/// A member's standing with one practice, read back from the `practice_progress`
/// view (which aggregates every play of it).
struct PracticeProgress: Identifiable, Hashable, Sendable {
    let kind: PracticeContentKind
    let contentID: Int
    let title: String
    let creator: String?
    let category: PracticeCategory?
    /// Where to pick the media back up.
    let positionSeconds: Int
    let durationSeconds: Int?
    /// Summed across every replay — this is the payout-relevant number.
    let totalSecondsPlayed: Int
    let completed: Bool
    let playCount: Int
    let lastPlayedAt: Date

    var id: String { "\(kind.rawValue)-\(contentID)" }

    /// How far through, 0–1. Zero when the length isn't known.
    var fraction: Double {
        guard let durationSeconds, durationSeconds > 0 else { return completed ? 1 : 0 }
        return min(1, max(0, Double(positionSeconds) / Double(durationSeconds)))
    }

    /// Started, but not finished — the set the "Continue" card draws from.
    /// A few seconds in doesn't count as started; that's usually a mis-tap.
    var isResumable: Bool {
        !completed && positionSeconds >= 10 && fraction < 0.95
    }

    var remainingLabel: String? {
        guard let durationSeconds, durationSeconds > positionSeconds else { return nil }
        let minutes = max(1, (durationSeconds - positionSeconds) / 60)
        return "\(minutes) min left"
    }

    /// Where this practice lives on the Practice tab, so a "Continue" tap can
    /// route to it. Total by design: every kind the ledger can hold has a
    /// section that opens it, and the exhaustive switch is what keeps that true
    /// — retiring a library again won't compile until someone decides where its
    /// history should land.
    var menuItem: PracticeMenuItem {
        switch kind {
        case .session:  return category.map(PracticeMenuItem.init(category:)) ?? .somatic
        case .journal:  return .journal
        case .exercise: return .movement
        case .recipe:   return .recipes
        }
    }
}

// MARK: - Practice menu (the cards on the Practice tab)

/// Every card on `PracticeView`. The first three are audio/video tracks backed
/// by `PracticeCategory`; the rest are bespoke content sections.
///
/// `movement` is the section the `Exercise` library lives in — the card reads
/// "Movement" while the items on it are still exercises. The content type keeps
/// its own name because `PracticeContentKind.exercise` is a DB contract.
enum PracticeMenuItem: String, Identifiable, Hashable, CaseIterable {
    case somatic, breathwork, meditation
    case journal, movement, recipes

    var id: String { rawValue }

    /// The card that hosts a given media track.
    init(category: PracticeCategory) {
        switch category {
        case .somatic:    self = .somatic
        case .breathwork: self = .breathwork
        case .meditation: self = .meditation
        }
    }

    /// The media category for the audio/video tracks; `nil` for bespoke sections.
    var mediaCategory: PracticeCategory? {
        switch self {
        case .somatic:    return .somatic
        case .breathwork: return .breathwork
        case .meditation: return .meditation
        default:          return nil
        }
    }

    var title: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.title
        case .journal:  return "Journal Prompts"
        case .movement: return "Movement"
        case .recipes:  return "Food Recipes"
        }
    }

    var blurb: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.blurb
        case .journal:  return "Sit with a question. Short prompts to move what words can reach."
        case .movement: return "Move with intention. Guided sequences for strength and mobility."
        case .recipes:  return "Eat to feel whole. Nourishing recipes for body and mind."
        }
    }

    var systemImage: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.systemImage
        case .journal:  return "pencil.and.scribble"
        case .movement: return "figure.strengthtraining.functional"
        case .recipes:  return "fork.knife"
        }
    }

    var imageName: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.imageName
        case .journal:  return "practice-journals"
        case .movement: return "practice-exercises"
        case .recipes:  return "practice-recipes"
        }
    }
}

// MARK: - Journal prompts (text)

struct JournalPrompt: Identifiable, Hashable {
    let id: Int
    /// The question itself — shown as the row title and the detail heading.
    let title: String
    /// Longer framing shown on the detail screen.
    let prompt: String
    /// Theme label (e.g. "Self-compassion"), used as the eyebrow.
    let theme: String
    let imageUrl: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: JournalPrompt, rhs: JournalPrompt) -> Bool { lhs.id == rhs.id }
}

extension JournalPrompt {
    static let all: [JournalPrompt] = [
        .init(id: 1, title: "What is your body asking for today?", prompt: "Close your eyes for a breath and scan from head to toe. Without fixing anything, name what you notice — tension, hunger, restlessness, ease. Let the answer come from sensation rather than thought.", theme: "Embodiment", imageUrl: "retreat-images/dolomites-2027-09.jpg"),
        .init(id: 2, title: "Name one thing you've outgrown.", prompt: "Think of a belief, a role, or a pattern that no longer fits who you're becoming. What would it feel like to set it down? Write to it as if saying goodbye.", theme: "Letting go", imageUrl: "retreat-images/sedona-2026-06.jpg"),
        .init(id: 3, title: "Where did you feel ease this week?", prompt: "Recall a moment — however small — when your shoulders dropped and time softened. Describe it in detail. What made it possible, and how might you invite more of it?", theme: "Gratitude", imageUrl: "retreat-images/bali-2026-07.jpg"),
        .init(id: 4, title: "What would self-compassion say right now?", prompt: "Picture the voice of someone who loves you unconditionally. Speak to yourself in their words about whatever you're carrying today. Notice how the body responds to kindness.", theme: "Self-compassion", imageUrl: "retreat-images/kyoto-2026-05.jpg"),
        .init(id: 5, title: "What are you ready to begin?", prompt: "Not the whole journey — just the first honest step. Name it, and name the smallest action you could take in the next 24 hours.", theme: "Intention", imageUrl: "retreat-images/mallorca-2027-07.jpg"),
    ]
}

// MARK: - Movement (guided exercise sequences)

struct ExerciseStep: Identifiable, Hashable {
    let id: Int
    let name: String
    /// Sets/reps or guidance, e.g. "3 sets · 12 reps" or "Hold 30 sec".
    let detail: String
}

struct Exercise: Identifiable, Hashable {
    let id: Int
    let title: String
    /// Primary focus, e.g. "Mobility", "Core".
    let focus: String
    let durationSeconds: Int
    let imageUrl: String
    let blurb: String
    let steps: [ExerciseStep]

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Exercise, rhs: Exercise) -> Bool { lhs.id == rhs.id }
}

extension Exercise {
    static let all: [Exercise] = [
        .init(id: 1, title: "Morning Mobility Flow", focus: "Mobility", durationSeconds: 600, imageUrl: "retreat-images/mallorca-2027-07.jpg", blurb: "A gentle full-body sequence to wake the joints and spine.", steps: [
            .init(id: 1, name: "Cat–Cow", detail: "8 slow reps"),
            .init(id: 2, name: "World's Greatest Stretch", detail: "5 reps each side"),
            .init(id: 3, name: "Hip Circles", detail: "10 each direction"),
            .init(id: 4, name: "Thoracic Rotations", detail: "8 each side"),
        ]),
        .init(id: 2, title: "Core Foundations", focus: "Core", durationSeconds: 720, imageUrl: "retreat-images/sedona-2026-06.jpg", blurb: "Build deep stability with slow, controlled holds.", steps: [
            .init(id: 1, name: "Dead Bug", detail: "3 sets · 10 reps"),
            .init(id: 2, name: "Forearm Plank", detail: "3 sets · 30 sec"),
            .init(id: 3, name: "Bird Dog", detail: "3 sets · 8 each side"),
            .init(id: 4, name: "Glute Bridge", detail: "3 sets · 12 reps"),
        ]),
        .init(id: 3, title: "Posture Reset", focus: "Alignment", durationSeconds: 480, imageUrl: "retreat-images/dolomites-2027-09.jpg", blurb: "Undo the desk slump and reopen the chest.", steps: [
            .init(id: 1, name: "Wall Angels", detail: "2 sets · 10 reps"),
            .init(id: 2, name: "Chin Tucks", detail: "2 sets · 12 reps"),
            .init(id: 3, name: "Doorway Chest Stretch", detail: "Hold 30 sec · 3x"),
        ]),
    ]
}

// MARK: - Food recipes

struct Recipe: Identifiable, Hashable {
    let id: Int
    let title: String
    /// Dietary angle or chef, e.g. "Anti-inflammatory".
    let lead: String
    let minutes: Int
    let servings: Int
    let imageUrl: String
    let blurb: String
    let ingredients: [String]
    let steps: [String]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
}

extension Recipe {
    static let all: [Recipe] = [
        .init(id: 1, title: "Golden Turmeric Lentils", lead: "Anti-inflammatory", minutes: 35, servings: 4, imageUrl: "retreat-images/bali-2026-07.jpg", blurb: "A warming, grounding bowl built on turmeric, ginger, and red lentils.",
              ingredients: ["1 cup red lentils", "1 onion, diced", "3 cloves garlic", "1 tbsp grated ginger", "2 tsp turmeric", "1 can coconut milk", "2 cups vegetable broth", "Salt & black pepper", "Fresh cilantro to finish"],
              steps: ["Sauté onion, garlic, and ginger until soft.", "Stir in turmeric and toast for 30 seconds.", "Add lentils, coconut milk, and broth; bring to a simmer.", "Cook 20–25 minutes until lentils are tender.", "Season, then finish with fresh cilantro."]),
        .init(id: 2, title: "Overnight Oats & Berries", lead: "Gut-friendly", minutes: 10, servings: 2, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "Prep tonight, wake to a fiber-rich breakfast that loves your microbiome.",
              ingredients: ["1 cup rolled oats", "1 cup milk of choice", "1/2 cup yogurt", "1 tbsp chia seeds", "1 tbsp maple syrup", "1 cup mixed berries"],
              steps: ["Combine oats, milk, yogurt, chia, and maple in a jar.", "Stir well and seal.", "Refrigerate overnight (at least 6 hours).", "Top with berries before serving."]),
        .init(id: 3, title: "Miso Glazed Salmon", lead: "Omega-3 rich", minutes: 25, servings: 2, imageUrl: "retreat-images/mallorca-2027-07.jpg", blurb: "A ten-minute glaze turns salmon into something restorative and bright.",
              ingredients: ["2 salmon fillets", "2 tbsp white miso", "1 tbsp honey", "1 tbsp rice vinegar", "1 tsp sesame oil", "Sliced scallions", "Steamed greens to serve"],
              steps: ["Whisk miso, honey, vinegar, and sesame oil.", "Coat salmon and rest 10 minutes.", "Roast at 200°C / 400°F for 12 minutes.", "Top with scallions; serve over steamed greens."]),
    ]
}

// MARK: - Circles (live now)

struct CommunityCircle: Identifiable, Hashable {
    let id: String
    let title: String
    let host: String
    let attendees: Int
    let timeLabel: String
    let isLive: Bool
}

extension CommunityCircle {
    static let mock: [CommunityCircle] = [
        CommunityCircle(id: "wih", title: "Women in Healing", host: "Mara Solé", attendees: 47, timeLabel: "Live now",  isLive: true),
        CommunityCircle(id: "mar", title: "Men at Rest",      host: "Theo Park", attendees: 18, timeLabel: "In 25 min", isLive: false),
    ]
}

// MARK: - Onboarding choices

struct IntentionOption: Identifiable, Hashable {
    let id: String
    let label: String
    let isSubtle: Bool
}

extension IntentionOption {
    static let all: [IntentionOption] = [
        .init(id: "travel",  label: "travel & retreat",  isSubtle: false),
        .init(id: "heal",    label: "heal emotionally",   isSubtle: false),
        .init(id: "move",    label: "move my body",       isSubtle: false),
        .init(id: "connect", label: "find my community",  isSubtle: false),
        .init(id: "rest",    label: "rest & recover",     isSubtle: false),
        .init(id: "other",   label: "something else",     isSubtle: true),
    ]
}

struct BodyStateOption: Identifiable, Hashable {
    let id: String
    let label: String
    let isSubtle: Bool
}

extension BodyStateOption {
    static let all: [BodyStateOption] = [
        .init(id: "soft",    label: "soft & open",       isSubtle: false),
        .init(id: "tender",  label: "tender today",       isSubtle: false),
        .init(id: "anxious", label: "anxious or racing",  isSubtle: false),
        .init(id: "numb",    label: "numb or shut down",  isSubtle: false),
        .init(id: "tired",   label: "tired & depleted",   isSubtle: false),
        .init(id: "other",   label: "self-describe",      isSubtle: true),
    ]
}

struct FrequencyOption: Identifiable, Hashable {
    let id: String
    let label: String
}

extension FrequencyOption {
    static let all: [FrequencyOption] = [
        .init(id: "daily",  label: "every day"),
        .init(id: "most",   label: "most days"),
        .init(id: "few",    label: "a few times a week"),
        .init(id: "weekly", label: "weekly, when I need it"),
    ]
}

// MARK: - Mood chips on Home

struct MoodChip: Identifiable, Hashable {
    let id: String
    let label: String
    /// Where this feeling points in the library. Selecting a chip rewrites
    /// Home's ritual card and sends "Begin now" here — the chips used to set
    /// state nothing read, which made the first interactive control on the
    /// main screen a no-op.
    let suggests: PracticeMenuItem
    /// Ritual-card headline for this mood.
    let ritual: String
    /// One line under the headline.
    let ritualLead: String
}

extension MoodChip {
    /// Shown when no mood is selected.
    static let defaultRitual = (
        title: "Begin where you are",
        lead: "A short practice for whatever today is",
        destination: PracticeMenuItem.journal
    )

    // Every mood points at a section that actually has content in v1
    // (journal / movement / recipes). The three media tracks are deliberately
    // absent — they read "Coming soon" until `practice_sessions` is seeded, and
    // a suggestion that lands on a locked card is a dead end. Each `ritual` /
    // `ritualLead` pair names something really in that section, so retiring a
    // library means rewriting the chips that point into it, not just repointing
    // them — Anxious and Tender both needed new copy when Personal Massages went.
    static let all: [MoodChip] = [
        .init(id: "anxious",  label: "Anxious",  suggests: .movement,
              ritual: "Move it through",       ritualLead: "Gentle movement to settle a racing body"),
        .init(id: "grateful", label: "Grateful", suggests: .journal,
              ritual: "Name it while it's here", ritualLead: "A prompt for what's already good"),
        .init(id: "tired",    label: "Tired",    suggests: .recipes,
              ritual: "Eat something warm",    ritualLead: "Nourishment that asks nothing of you"),
        .init(id: "joyful",   label: "Joyful",   suggests: .movement,
              ritual: "Move with it",          ritualLead: "Let the body spend some of that"),
        .init(id: "tender",   label: "Tender",   suggests: .journal,
              ritual: "Speak to yourself kindly", ritualLead: "A prompt for a soft day"),
        .init(id: "calm",     label: "Calm",     suggests: .journal,
              ritual: "Stay a while",          ritualLead: "A prompt to sit with the quiet"),
        .init(id: "lost",     label: "Lost",     suggests: .journal,
              ritual: "Find one true thing",   ritualLead: "Short questions for when the map is gone"),
        .init(id: "hopeful",  label: "Hopeful",  suggests: .movement,
              ritual: "Build on it",           ritualLead: "A sequence for strength and momentum"),
        .init(id: "sad",      label: "Sad",      suggests: .journal,
              ritual: "Let it have room",      ritualLead: "A prompt that doesn't rush you"),
        .init(id: "peaceful", label: "Peaceful", suggests: .recipes,
              ritual: "Make something slow",   ritualLead: "Cooking as the practice"),
        .init(id: "angry",    label: "Angry",    suggests: .movement,
              ritual: "Put it somewhere",      ritualLead: "Move the heat out through the body"),
        .init(id: "inspired", label: "Inspired", suggests: .journal,
              ritual: "Catch it in writing",   ritualLead: "Before the thought moves on"),
    ]
}
