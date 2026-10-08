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
    /// `avatars/<user id>/<uuid>.jpg` in Storage, or nil for no photo. Written
    /// by `SupabaseService.setAvatar`, never by `upsertProfile`.
    var avatarUrl: String? = nil
    /// Whether finished practices appear in the Community feed. Opt-out,
    /// on the You tab. Never touched by `upsertProfile`.
    var shareActivity: Bool = true
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

    /// The retreat's last day is behind us — what the You tab needs before it
    /// calls a retreat one the member has *been on*. Compared in the device's
    /// calendar, the same one `RetreatRow` parsed the date in: this is a
    /// question about the member's own past, not about keeping a shared catalog
    /// consistent across time zones, which is what `hasBegun`'s UTC is for.
    var hasEnded: Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: endDate) < calendar.startOfDay(for: .now)
    }

    /// "July 21–26, 2027". `when` omits the year because the catalog only ever
    /// shows the months ahead; a retreat in someone's history needs it.
    var whenWithYear: String {
        "\(when), \(Calendar.current.component(.year, from: endDate))"
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

// MARK: - Digital programs (the Programs tab)

/// A self-paced, multi-day guided journey. The catalog row; the day-by-day
/// content hangs off `curriculum`.
///
/// Sourced from the `programs` table. There is deliberately **no** offline
/// fallback for the real catalog — `mock` below exists for previews and the
/// DEBUG `-preview-*` screens only, exactly as `Retreat.mock` does.
struct Program: Identifiable, Hashable {
    let id: String
    let title: String
    /// The guide who leads it.
    let lead: String
    /// A display date range, and normally **nil**. A program is self-paced, so
    /// the meta line is derived from `days` and cannot drift from the content.
    /// Set it only to deliberately override that — the same opt-out
    /// `RetreatExperience.dateRange` offers the brochure.
    let when: String?
    let days: Int
    let imageUrl: String
    let blurb: String?
    /// The authored days. Nil when the column is empty **or when it failed to
    /// decode** — see `ProgramRow.decodedCurriculum`, which fails soft. A
    /// program with no curriculum is shown in the catalog but cannot be
    /// started, because there is nothing to start.
    let curriculum: ProgramCurriculum?
    /// False for a draft, or for a program taken down after members joined it.
    /// The catalog never sees one (`fetchPrograms` filters on it); the You tab
    /// can, because a program someone finished is still part of their history
    /// even once it's gone from the shelf — it just can't be opened any more.
    let published: Bool
    /// The guide's `instructors` row, when linked (0019). `lead` is its name.
    let instructorID: String?

    init(id: String, title: String, lead: String, when: String? = nil, days: Int,
         imageUrl: String, blurb: String? = nil, curriculum: ProgramCurriculum? = nil,
         published: Bool = true, instructorID: String? = nil) {
        self.id = id
        self.title = title
        self.lead = lead
        self.when = when
        self.days = days
        self.imageUrl = imageUrl
        self.blurb = blurb
        self.curriculum = curriculum
        self.published = published
        self.instructorID = instructorID
    }

    /// What the catalog card and the detail header say about length.
    var metaLine: String {
        when ?? "\(days) \(days == 1 ? "day" : "days") · Self-paced"
    }

    /// The days actually authored. The catalog's `days` column is a display
    /// number and the two can disagree if someone edits one and not the other;
    /// everything that walks the program uses this.
    var authoredDays: [ProgramDay] { curriculum?.days ?? [] }

    /// A program with no authored days cannot be enrolled in.
    var isStartable: Bool { !authoredDays.isEmpty }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Program, rhs: Program) -> Bool { lhs.id == rhs.id }
}

/// The hand-authored `programs.curriculum` document.
///
/// Decoding **fails soft** at the row level (see `ProgramRow`), which means a
/// broken curriculum looks exactly like an unauthored one. When someone says a
/// program "has no days", check the log for a decode error before assuming the
/// column is empty — the same trap `retreats.experience` carries.
struct ProgramCurriculum: Hashable, Sendable, Decodable {
    /// One paragraph on the arc of the whole program.
    let overview: String?
    let days: [ProgramDay]
    /// Shown once the last day is complete.
    let closing: ProgramClosing?

    enum CodingKeys: String, CodingKey { case overview, days, closing }

    init(overview: String? = nil, days: [ProgramDay], closing: ProgramClosing? = nil) {
        self.overview = overview
        self.days = days.sorted { $0.day < $1.day }
        self.closing = closing
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.overview = try c.decodeIfPresent(String.self, forKey: .overview)
        self.closing = try c.decodeIfPresent(ProgramClosing.self, forKey: .closing)
        // Sorted rather than trusted: the unlock rule walks days in order, and
        // a curriculum authored out of sequence would otherwise gate the wrong
        // one.
        self.days = (try c.decodeIfPresent([ProgramDay].self, forKey: .days) ?? [])
            .sorted { $0.day < $1.day }
    }
}

struct ProgramClosing: Hashable, Sendable, Decodable {
    let title: String
    let body: String
}

/// One day of a program.
struct ProgramDay: Identifiable, Hashable, Sendable, Decodable {
    /// 1-based. This is the identity the completion rows are keyed on, so it
    /// must not be renumbered once a program is live.
    let day: Int
    let title: String
    let intention: String?
    let imageUrl: String?
    let activities: [ProgramActivity]

    var id: Int { day }

    enum CodingKeys: String, CodingKey {
        case day, title, intention, activities
        case imageUrl = "image_url"
    }

    init(day: Int, title: String, intention: String? = nil,
         imageUrl: String? = nil, activities: [ProgramActivity]) {
        self.day = day
        self.title = title
        self.intention = intention
        self.imageUrl = imageUrl
        self.activities = activities
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let day = try c.decode(Int.self, forKey: .day)
        self.day = day
        self.title = try c.decode(String.self, forKey: .title)
        self.intention = try c.decodeIfPresent(String.self, forKey: .intention)
        self.imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        // Lossy on purpose. One unreadable activity — a `kind` this build
        // doesn't know, a missing id — costs that activity, not the program.
        // The alternative is a single typo in hand-authored JSON emptying the
        // whole tab.
        var list = try c.nestedUnkeyedContainer(forKey: .activities)
        var parsed: [ProgramActivity] = []
        while !list.isAtEnd {
            if let activity = try? list.decode(ProgramActivity.self) {
                parsed.append(activity)
            } else {
                _ = try? list.decode(AnyDecodableSkip.self)
                // `day`, not `self.day`: a log interpolation is an autoclosure
                // and can't capture a mutating self mid-initialiser.
                Log.data.error("Program day \(day, privacy: .public): skipped an unreadable activity")
            }
        }
        self.activities = parsed
    }
}

/// Consumes one element of an unkeyed container whose contents we don't care
/// about, so a failed `decode` can be stepped over instead of wedging the loop.
private struct AnyDecodableSkip: Decodable {
    init(from decoder: any Decoder) throws {}
}

/// A pointer from a program day into one of the practice libraries.
///
/// It is a *reference*, not a copy: the content itself still lives in
/// `practice_sessions` or the hardcoded libraries, and playing it records to
/// `practice_plays` exactly as it would from the Practice tab. A creator is
/// paid the same whether their session was found in the library or in a
/// program.
struct ProgramActivity: Identifiable, Hashable, Sendable, Decodable {
    let kind: PracticeContentKind
    let contentID: Int
    /// An optional line of framing from the guide, shown under the row.
    let note: String?

    /// Matches `PracticeProgress.id`, which is how completion is looked up.
    var id: String { "\(kind.rawValue)-\(contentID)" }

    enum CodingKeys: String, CodingKey {
        case kind, note
        case contentID = "content_id"
    }

    init(kind: PracticeContentKind, contentID: Int, note: String? = nil) {
        self.kind = kind
        self.contentID = contentID
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .kind)
        // Strict, unlike `PracticePlay`'s read-side `?? .session`: mis-filing a
        // curriculum entry under the wrong library would send the member to the
        // wrong screen, and the lossy decode above turns this throw into a
        // skipped row rather than a broken program.
        guard let kind = PracticeContentKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c,
                debugDescription: "Unknown practice content kind '\(raw)'")
        }
        self.kind = kind
        self.contentID = try c.decode(Int.self, forKey: .contentID)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

/// A member's standing with one program, from `program_enrollments`.
struct ProgramEnrollment: Hashable, Sendable {
    let programID: String
    let enrolledAt: Date
    let completedAt: Date?
}

/// One finished day, from `program_day_completions`.
///
/// `completedAt` is a **server** timestamp and the input to the next day's
/// unlock. It is compared against `practice_progress.last_played_at`, which is
/// also server-stamped, so the two are on the same clock — the device's only
/// contribution is deciding which calendar day a given instant falls in.
struct ProgramDayCompletion: Hashable, Sendable {
    let programID: String
    let day: Int
    let completedAt: Date
}

/// Whether a day can be opened, and if not, why not.
///
/// Both halves of the rule are represented, because they need different words:
/// "finish today first" and "come back tomorrow" are not the same message and
/// a single `locked` case would have to guess which one to show.
enum ProgramDayState: Hashable, Sendable {
    /// Every activity done, on the date it was finished.
    case complete(Date)
    /// Open now.
    case open
    /// The previous day is done, but the calendar hasn't turned over yet.
    case opens(Date)
    /// The previous day is still unfinished.
    case awaitingPreviousDay

    var isOpen: Bool { self == .open }
    var isComplete: Bool { if case .complete = self { return true }; return false }
}

extension Program {
    /// Preview / DEBUG fixture only — never a fallback for the live catalog.
    /// See `RetreatsLoadFailure` for why an invented catalogue must not stand
    /// in for a failed fetch.
    static let mock: [Program] = [
        Program(id: "finding-ground", title: "Finding Ground", lead: "Alma Guerra",
                days: 7, imageUrl: "retreat-images/dolomites-2027-09.jpg",
                blurb: "Seven days of returning to the body — breath, movement, reflection and food, one day at a time.",
                curriculum: ProgramCurriculum(
                    overview: "A week of small, repeatable returns. Each day asks for twenty minutes and gives back a little more room than you had.",
                    days: [
                        ProgramDay(day: 1, title: "Arriving", intention: "Land before you ask anything of the body.",
                                   imageUrl: "retreat-images/dolomites-2027-09.jpg",
                                   activities: [.init(kind: .journal, contentID: 1, note: "Answer from sensation, not from thought."),
                                                .init(kind: .exercise, contentID: 1)]),
                        ProgramDay(day: 2, title: "Steadiness", intention: "Find the floor. Everything else is built on it.",
                                   imageUrl: "retreat-images/sedona-2026-06.jpg",
                                   activities: [.init(kind: .exercise, contentID: 4, note: "Slow is the whole instruction."),
                                                .init(kind: .recipe, contentID: 1)]),
                        ProgramDay(day: 3, title: "Letting go", intention: "Set down one thing you have been carrying out of habit.",
                                   imageUrl: "retreat-images/kyoto-2026-05.jpg",
                                   activities: [.init(kind: .journal, contentID: 2),
                                                .init(kind: .exercise, contentID: 3)]),
                    ],
                    closing: ProgramClosing(title: "You have come back seven times",
                                            body: "That is the practice — not the week, but the returning.")),
                instructorID: "alma-guerra"),
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

    /// "Before you begin": shown above the track's sessions. Breathwork can
    /// make someone light-headed, and somatic work can bring up more than
    /// expected, so both say so — and that none of it is medical advice —
    /// before a session is chosen. Meditation needs none.
    var safetyNote: String? {
        switch self {
        case .breathwork:
            return "Breathe seated or lying down, never while driving or in water. If you feel light-headed or unwell, stop and breathe normally. This isn't medical advice: if you're pregnant or have a heart, lung or seizure condition, check with your doctor first."
        case .somatic:
            return "Move gently and stay within what feels comfortable. Pause whenever you need to, and stop if anything hurts or feels like too much. This isn't medical or psychological advice: if you have an injury or a health condition, check with your doctor first."
        case .meditation:
            return nil
        }
    }

    /// The same care in one line, under the title while a session plays.
    var safetyReminder: String? {
        switch self {
        case .breathwork: return "Stop if you feel light-headed, and breathe normally."
        case .somatic:    return "Go gently, and stop if anything hurts."
        case .meditation: return nil
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
    /// The guide it is credited to, when linked (0019) — what lets the player
    /// open their profile.
    var instructorID: String? = nil

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
    /// The guide's `instructors` row, when the session is linked to one (0019)
    /// — what makes "with …" lead somewhere. `lead` is kept equal to that
    /// guide's name server-side, so the two can't disagree.
    var instructorID: String? = nil

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    var media: MediaItem {
        MediaItem(id: id, title: title, lead: lead, imageUrl: imageUrl,
                  mediaKind: mediaKind, storagePath: storagePath, durationSeconds: durationSeconds,
                  contentKind: .session, category: category, instructorID: instructorID)
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

    /// Whether a finished sitting counts as a **class** on the You tab, and
    /// whether its time counts toward minutes practiced. Guided practice does —
    /// the three media tracks and the Movement library, where yoga lives.
    /// Writing against a prompt and reading a recipe are practice, and they keep
    /// a streak alive, but they are not a class. Exhaustive on purpose, like
    /// `creditsCreator`: a new library won't compile until someone decides.
    var countsAsClass: Bool {
        switch self {
        case .session, .exercise:  return true
        case .journal, .recipe:    return false
        }
    }
}

/// One row of the member's own `practice_plays` ledger, reduced to what the
/// You tab's numbers are computed from. Keyed by `eventID` — the row's
/// `client_event_id`, the same key the ledger upserts on — so a sitting that
/// is still heartbeating replaces its own entry rather than adding another.
struct PracticePlayRecord: Hashable, Sendable {
    let eventID: UUID
    let kind: PracticeContentKind
    let secondsPlayed: Int
    let completed: Bool
    /// Server-stamped. Which local calendar day it falls on is what a streak
    /// counts.
    let startedAt: Date
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

    /// `Recipe.angle` is a dietary angle ("Anti-inflammatory"), not a person,
    /// so it is deliberately NOT passed as the creator — a payout run must
    /// never try to pay "Gut-friendly".
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

// MARK: - Written practices (journal prompts, movement, recipes)
//
// Each library is a table (0021) — `journal_prompts`, `exercises`, `recipes` —
// read through `WrittenPracticeStore`. They lived here as `.all` arrays until
// 2026-09-29, which made every new prompt and every typo fix a release.
//
// The ids are a contract with the practice ledger, program curricula and a
// member's saved reflections, none of which can follow a renumbering. Each one
// names its guide on its own row (`instructorID`, 0022), as sessions and
// digital retreats do. `.mock` on each type is a preview / DEBUG fixture only — never a
// fallback for a library that failed to load.

struct JournalPrompt: Identifiable, Hashable, Codable {
    let id: Int
    /// The question itself — shown as the row title and the detail heading.
    let title: String
    /// Longer framing shown on the detail screen.
    let prompt: String
    /// Theme label (e.g. "Self-compassion"), used as the eyebrow.
    let theme: String
    let imageUrl: String
    /// The guide on its page and in whose library it appears. Display only —
    /// the written libraries take no part in payouts (`creditsCreator`).
    var instructorID: String? = nil

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: JournalPrompt, rhs: JournalPrompt) -> Bool { lhs.id == rhs.id }
}

extension JournalPrompt {
    /// Preview / DEBUG fixture only. Id 3 is the prompt `-preview-instructors`
    /// credits to its second guide.
    static let mock: [JournalPrompt] = [
        .init(id: 1, title: "What is your body asking for today?", prompt: "Close your eyes for a breath and scan from head to toe. Without fixing anything, name what you notice.", theme: "Embodiment", imageUrl: "retreat-images/dolomites-2027-09.jpg"),
        .init(id: 3, title: "Where did you feel ease this week?", prompt: "Recall a moment — however small — when your shoulders dropped and time softened. Describe it in detail.", theme: "Gratitude", imageUrl: "retreat-images/bali-2026-07.jpg"),
    ]
}

struct ExerciseStep: Identifiable, Hashable, Codable {
    /// Its place in the sequence, from 1. Steps are stored as an ordered list,
    /// so the position is their only identity.
    let id: Int
    let name: String
    /// Sets/reps or guidance, e.g. "3 sets · 12 reps" or "Hold 30 sec". Nil
    /// when the name says it all.
    let detail: String?
}

struct Exercise: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    /// Primary focus, e.g. "Mobility", "Core".
    let focus: String
    let durationSeconds: Int
    let imageUrl: String
    let blurb: String
    let steps: [ExerciseStep]
    /// See `JournalPrompt.instructorID`.
    var instructorID: String? = nil

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Exercise, rhs: Exercise) -> Bool { lhs.id == rhs.id }
}

extension Exercise {
    /// Preview / DEBUG fixture only. Id 1 is the sequence `-preview-instructors`
    /// credits to its first guide.
    static let mock: [Exercise] = [
        .init(id: 1, title: "Morning Mobility Flow", focus: "Mobility", durationSeconds: 600, imageUrl: "retreat-images/mallorca-2027-07.jpg", blurb: "A gentle full-body sequence to wake the joints and spine.", steps: [
            .init(id: 1, name: "Cat–Cow", detail: "8 slow reps"),
            .init(id: 2, name: "World's Greatest Stretch", detail: "5 reps each side"),
            .init(id: 3, name: "Hip Circles", detail: "10 each direction"),
        ]),
        .init(id: 5, title: "Evening Yin", focus: "Yoga", durationSeconds: 1200, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "Long, supported holds for the end of the day.", steps: [
            .init(id: 1, name: "Butterfly", detail: "Hold 3 min"),
            .init(id: 2, name: "Savasana", detail: nil),
        ]),
    ]
}

struct Recipe: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    /// A dietary angle, e.g. "Anti-inflammatory" — never a person. A recipe's
    /// guide, if it has one, is `instructorID`.
    let angle: String
    let minutes: Int
    let servings: Int
    let imageUrl: String
    let blurb: String
    let ingredients: [String]
    let steps: [String]
    /// See `JournalPrompt.instructorID`.
    var instructorID: String? = nil

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
}

extension Recipe {
    /// Preview / DEBUG fixture only. Id 1 is the recipe `-preview-instructors`
    /// credits to its first guide.
    static let mock: [Recipe] = [
        .init(id: 1, title: "Golden Turmeric Lentils", angle: "Anti-inflammatory", minutes: 35, servings: 4, imageUrl: "retreat-images/bali-2026-07.jpg", blurb: "A warming, grounding bowl built on turmeric, ginger, and red lentils.",
              ingredients: ["1 cup red lentils", "1 onion, diced", "2 tsp turmeric", "1 can coconut milk"],
              steps: ["Sauté the onion until soft.", "Stir in the turmeric, then the lentils and coconut milk.", "Simmer until tender."]),
    ]
}

/// The three written libraries as the app holds them: published rows only, in
/// the team's order.
struct WrittenLibrary: Hashable, Sendable, Codable {
    var journals: [JournalPrompt] = []
    var exercises: [Exercise] = []
    var recipes: [Recipe] = []

    static let empty = WrittenLibrary()

    /// Preview / DEBUG fixture only.
    static let mock = WrittenLibrary(journals: JournalPrompt.mock,
                                     exercises: Exercise.mock,
                                     recipes: Recipe.mock)

    var isEmpty: Bool { journals.isEmpty && exercises.isEmpty && recipes.isEmpty }

    func journal(id: Int) -> JournalPrompt? { journals.first { $0.id == id } }
    func exercise(id: Int) -> Exercise? { exercises.first { $0.id == id } }
    func recipe(id: Int) -> Recipe? { recipes.first { $0.id == id } }
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

// MARK: - Community

/// Another member as the Community tab shows them: an id, a name abbreviated
/// server-side ("Hugo D." — the full name never leaves the row), and a photo.
/// Read from the `community_members` view and `search_members()`.
struct CommunityMember: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    /// `avatars/<id>/<uuid>.jpg`, resolved by `ImageSource`; nil for initials.
    let avatarUrl: String?
}

/// "75.7k present" — how many people are with a practice or a digital
/// retreat, and up to three of their faces. From `practice_presence()` /
/// `program_presence()` (0018).
///
/// For a practice, present = started it in the last 24 hours. For a program,
/// = joined, not finished, and active in it in the last 14 days. The server
/// never answers below 3 people, puts friends first among the faces, leaves
/// out the viewer and anyone who opted out of sharing, and sends no faces for
/// a journal prompt — so `faces` may hold fewer than three, or none.
struct Presence: Hashable, Sendable {
    let count: Int
    let faces: [CommunityMember]

    /// "840 present", "1.2k present", "75.7k present", "1.1M present".
    var label: String { "\(Self.compact(count)) present" }

    /// Rounded DOWN to one decimal, so the line never claims someone who
    /// isn't there: 1,999 reads "1.9k", not "2k".
    static func compact(_ n: Int) -> String {
        func scaled(_ unit: Int, _ suffix: String) -> String {
            let tenths = n / (unit / 10)
            let whole = tenths / 10, rest = tenths % 10
            return rest == 0 ? "\(whole)\(suffix)" : "\(whole).\(rest)\(suffix)"
        }
        switch n {
        case ..<1_000:     return "\(n)"
        case ..<1_000_000: return scaled(1_000, "k")
        default:           return scaled(1_000_000, "M")
        }
    }
}

/// One line of the feed: a member finished a practice. Read from the
/// `community_activity` view, which already excludes journal prompts, anything
/// unfinished, and members who have opted out.
struct CommunityActivity: Identifiable, Hashable, Sendable {
    /// The play's id — one row per sitting, so a session done twice is two lines.
    let id: UUID
    let member: CommunityMember
    let kind: PracticeContentKind
    let contentID: Int
    let title: String
    let category: PracticeCategory?
    let completedAt: Date
    /// How many members liked this line, and whether the viewer is one of
    /// them. Both come from the view per request, so the likes table itself
    /// stays scoped to the people it concerns.
    var likeCount: Int = 0
    var likedByMe: Bool = false

    /// The eyebrow under the line: the track for a session, the library otherwise.
    var kindLabel: String {
        if let category { return category.title }
        switch kind {
        case .session:  return "Session"
        case .exercise: return "Movement"
        case .recipe:   return "Recipe"
        case .journal:  return "Journal"
        }
    }
}

/// A friend request, or the friendship it became. `status` is the server's;
/// which side of it *this* member is on is `direction`.
struct Friendship: Identifiable, Hashable, Sendable {
    enum Status: String, Hashable, Sendable { case pending, accepted }
    enum Direction: Hashable, Sendable {
        /// This member asked.
        case sent
        /// This member was asked.
        case received
    }

    let requesterID: UUID
    let addresseeID: UUID
    let status: Status
    let createdAt: Date
    /// The other person, resolved through `community_members`. Nil only if
    /// they have since deleted their account (the row cascades soon after).
    var other: CommunityMember?
    let direction: Direction

    var id: String { "\(requesterID.uuidString)-\(addresseeID.uuidString)" }
    var otherID: UUID { direction == .sent ? addresseeID : requesterID }
    var isAccepted: Bool { status == .accepted }
}

/// Where a member stands relative to me, for the button beside their name.
enum FriendStanding: Hashable {
    case none
    case requested
    case awaitingMyAnswer
    case friends
}

/// "Alma G. liked your Confidence Boost practice." Read from the
/// `member_notifications` view; written only by the like trigger.
struct LikeNotification: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Nil once the liker has deleted their account: "Someone liked…".
    let actor: CommunityMember?
    let playID: UUID?
    let practiceTitle: String?
    let createdAt: Date
    let readAt: Date?

    var isUnread: Bool { readAt == nil }
}

/// Why a member is being reported (0028, `report-member`). The raw values are
/// `member_reports.reason`, and the titles are what the team's email says —
/// the Edge Function holds the same strings, so change both together.
enum ReportReason: String, CaseIterable, Identifiable, Hashable, Sendable, Encodable {
    case photo, name, harassment, spam, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo:      "Inappropriate photo"
        case .name:       "Offensive name"
        case .harassment: "Harassment or unwanted contact"
        case .spam:       "Spam or a fake account"
        case .other:      "Something else"
        }
    }
}

/// One report, as the Report sheet sends it to `report-member`. Who is
/// reporting comes from the session's JWT, never from here.
struct MemberReport: Encodable, Hashable, Sendable {
    let reportedID: UUID
    /// The feed line it was reported from, if any.
    let playID: UUID?
    let reason: ReportReason
    /// The reporter's note, trimmed; nil when they wrote nothing.
    let details: String?

    /// The longest note the sheet takes (the server caps at 1,000).
    static let maxDetails = 500

    /// Nil until a reason is chosen — the one thing a report can't do without.
    init?(reportedID: UUID, playID: UUID?, reason: ReportReason?, details: String) {
        guard let reason else { return nil }
        self.reportedID = reportedID
        self.playID = playID
        self.reason = reason
        let note = String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxDetails))
        self.details = note.isEmpty ? nil : note
    }

    enum CodingKeys: String, CodingKey {
        case reportedID = "reported_id", playID = "play_id", reason, details
    }
}

// MARK: - Instructors

/// A guide who teaches in the app, from the `instructors` table (0019).
///
/// A row the team writes, the way a retreat is — not a member account. A guide
/// who also has an account is linked to it server-side, and that link never
/// reaches the app (see 0019).
struct Instructor: Identifiable, Hashable, Sendable {
    /// A slug ("alma-guerra"): what `practice_sessions.instructor_id` and
    /// `programs.instructor_id` point at.
    let id: String
    let name: String
    /// What they teach, in a few words: "Breathwork · Somatic therapy".
    let title: String?
    let bio: String?
    /// `instructor-photos/<id>.jpg`, resolved by `ImageSource`; nil for the
    /// initial on its tone.
    let photoUrl: String?

    /// "Alma" — for copy that speaks about them ("Practices with Alma").
    var firstName: String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }
}

/// The numbers on a guide's page, from `instructor_social()`.
///
/// `following` is the guides this guide's own member account follows —
/// members follow guides, so that is what a guide can follow. Zero for a guide
/// with no account linked. `faces` never includes the viewer and only ever
/// holds members who share their practice, so it can be shorter than
/// `followers` suggests, or empty.
struct InstructorSocial: Hashable, Sendable {
    var followers: Int
    var following: Int
    var followedByMe: Bool
    /// The viewer IS this guide: no Follow button on your own page.
    var isMe: Bool
    var faces: [CommunityMember]

    static let empty = InstructorSocial(followers: 0, following: 0, followedByMe: false,
                                        isMe: false, faces: [])

    /// "Followed by Alma G., Theo R. and 1,203 others".
    ///
    /// At most two names, "you" first when the viewer follows too — the
    /// server leaves the viewer out of `faces`, so without it they would be
    /// hidden in "others". Nil when nobody can be named: the count alone says
    /// it. `others` is clamped, because the count and the faces come from one
    /// read but an optimistic follow moves only the count.
    func followedByLine(locale: Locale = .current) -> String? {
        var names: [String] = followedByMe ? ["you"] : []
        names += faces.prefix(2 - names.count).map(\.displayName)
        guard !names.isEmpty else { return nil }
        let others = max(0, followers - names.count)
        let named = names.count == 1 ? names[0] : names.joined(separator: others == 0 ? " and " : ", ")
        switch others {
        case 0:  return "Followed by \(named)"
        case 1:  return "Followed by \(named) and 1 other"
        default: return "Followed by \(named) and \(others.formatted(.number.locale(locale))) others"
        }
    }
}

/// What a guide has published: their digital retreats, their sessions on the
/// Practice tab, and the written practices that name them.
struct InstructorLibrary: Hashable, Sendable {
    var programs: [Program]
    var sessions: [PracticeSession]
    var exercises: [Exercise] = []
    var recipes: [Recipe] = []
    var journals: [JournalPrompt] = []

    var isEmpty: Bool { count == 0 }
    var count: Int { programs.count + sessions.count + exercises.count + recipes.count + journals.count }

    /// Takes the guide's own practices from the written libraries, in each
    /// library's order. The libraries hold published rows only, so a practice
    /// that has been taken down isn't listed.
    init(programs: [Program], sessions: [PracticeSession], written: WrittenLibrary,
         instructorID: String) {
        self.programs = programs
        self.sessions = sessions
        self.exercises = written.exercises.filter { $0.instructorID == instructorID }
        self.recipes = written.recipes.filter { $0.instructorID == instructorID }
        self.journals = written.journals.filter { $0.instructorID == instructorID }
    }
}

// MARK: - Guide dashboard

/// A calendar month in UTC: the month a play, a pool and a payout are counted
/// in (0026), so a play belongs to one month wherever it was heard. Labelled
/// in UTC too: formatted in the device's zone, "2026-10-01" is still September
/// anywhere west of Greenwich.
struct PayoutMonth: Hashable, Comparable, Sendable {
    let year: Int
    /// 1–12.
    let month: Int

    init(year: Int, month: Int) {
        // Normalised, so stepping back from January lands in December.
        let (years, months) = (year * 12 + (month - 1)).quotientAndRemainder(dividingBy: 12)
        self.year = months < 0 ? years - 1 : years
        self.month = (months < 0 ? months + 12 : months) + 1
    }

    /// The server's shape for a month: its first day, "2026-10-01".
    init?(isoDate: String) {
        let parts = isoDate.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        self.init(year: year, month: month)
    }

    static func < (a: PayoutMonth, b: PayoutMonth) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }

    func advanced(by months: Int) -> PayoutMonth {
        PayoutMonth(year: year, month: month + months)
    }

    static let utc = TimeZone(identifier: "UTC")!

    /// Midnight UTC on its first day.
    var start: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    private func formatted(_ style: (Date.FormatStyle) -> Date.FormatStyle, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: Self.utc)
        return start.formatted(style(base))
    }

    /// "October 2026".
    func title(locale: Locale = .current) -> String {
        formatted({ $0.month(.wide).year() }, locale: locale)
    }

    /// "October".
    func name(locale: Locale = .current) -> String {
        formatted({ $0.month(.wide) }, locale: locale)
    }

    /// "Oct", under a bar.
    func shortName(locale: Locale = .current) -> String {
        formatted({ $0.month(.abbreviated) }, locale: locale)
    }
}

/// Money in its minor unit, in its own currency: what a pool or a payout is
/// stored as, so nothing is rounded before it's shown.
struct PayoutAmount: Hashable, Sendable {
    let cents: Int
    /// Lowercase ISO 4217, as stored ("usd").
    let currency: String

    func formatted(locale: Locale = .current) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currency.uppercased()).locale(locale))
    }
}

/// One month of a guide's numbers, from `guide_dashboard()`.
///
/// `people`, `plays` and `completions` count everything of theirs anyone
/// opened. `secondsHeard` counts their sessions only: it is what the pool is
/// shared by, and the written libraries take no part in payouts
/// (`creditsCreator`). Their own plays are in none of these.
struct GuideMonth: Identifiable, Hashable, Sendable {
    let month: PayoutMonth
    let people: Int
    let plays: Int
    let completions: Int
    let secondsHeard: Int
    /// Every guide's seconds heard that month: the denominator of the share.
    let poolSeconds: Int
    /// The month's pool, once the team has set it.
    let pool: PayoutAmount?
    /// Their cut of `pool`. Nil exactly when the pool is.
    let earned: PayoutAmount?
    let paidAt: Date?

    var id: PayoutMonth { month }

    var minutesHeard: Int { secondsHeard / 60 }

    /// Their share of every guide's minutes heard, 0–1. Nil when no guide's
    /// sessions were heard at all: there's nothing to have a share of.
    var share: Double? {
        poolSeconds > 0 ? min(1, Double(secondsHeard) / Double(poolSeconds)) : nil
    }

    /// A month with nothing in it: before their first play, or a quiet one.
    static func empty(_ month: PayoutMonth) -> GuideMonth {
        GuideMonth(month: month, people: 0, plays: 0, completions: 0, secondsHeard: 0,
                   poolSeconds: 0, pool: nil, earned: nil, paidAt: nil)
    }

    /// Where a month's money stands. "Not set" and "not paid" call for different
    /// words: the first has no figure at all, the second has one that is owed.
    enum Standing: Hashable {
        /// The month is still running and its pool is set: what the share so
        /// far would be worth. It moves until the month closes.
        case estimate(PayoutAmount)
        /// No pool entered for this month yet, running or past. No figure is
        /// shown: there is nothing honest to multiply the share by.
        case awaitingPool
        /// Closed, with a pool, and not paid out yet.
        case due(PayoutAmount)
        case paid(PayoutAmount, on: Date)
    }

    /// `thisMonth` is the server's running month, not the device's.
    func standing(thisMonth: PayoutMonth) -> Standing {
        guard let earned else { return .awaitingPool }
        if let paidAt { return .paid(earned, on: paidAt) }
        return month >= thisMonth ? .estimate(earned) : .due(earned)
    }
}

/// One practice of a guide's that someone opened, all time.
struct GuidePracticeStat: Identifiable, Hashable, Sendable {
    let kind: PracticeContentKind
    let contentID: Int
    /// The title it was last played under.
    let title: String
    let people: Int
    let peopleThisMonth: Int
    let plays: Int
    let completions: Int
    /// Sessions only; zero for the written libraries, which aren't heard.
    let secondsHeard: Int

    var id: String { "\(kind.rawValue)-\(contentID)" }
}

/// A digital retreat a guide leads. `joined` counts current enrolments:
/// leaving a program removes the row (0013).
struct GuideProgramStat: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let joined: Int
    let finished: Int
}

/// Everything on a guide's dashboard, for the member whose account the team
/// linked to them (`instructors.user_id`). Aggregates only: no member is ever
/// named or counted on their own.
struct GuideDashboard: Hashable, Sendable {
    struct Totals: Hashable, Sendable {
        let people: Int
        let plays: Int
        let completions: Int
        let secondsHeard: Int

        var minutesHeard: Int { secondsHeard / 60 }
    }

    let instructorID: String
    let name: String
    let photoUrl: String?
    /// The running month on the server's clock (UTC).
    let thisMonth: PayoutMonth
    let totals: Totals
    /// Newest first, from the month of their first play to `thisMonth`, quiet
    /// months included.
    let months: [GuideMonth]
    /// Most people first.
    let practices: [GuidePracticeStat]
    let programs: [GuideProgramStat]

    /// This month so far. The server always sends it; a zero month stands in
    /// if it ever doesn't, rather than last month's figures under this
    /// month's name.
    var current: GuideMonth {
        months.first { $0.month == thisMonth } ?? .empty(thisMonth)
    }

    /// Closed months, newest first.
    var pastMonths: [GuideMonth] {
        months.filter { $0.month < thisMonth }
    }

    /// The last `count` months up to this one, oldest first, for the chart.
    /// Months before their first play are filled with zeros, so a new guide's
    /// chart has its full width rather than one bar stretched across it.
    func recentMonths(_ count: Int) -> [GuideMonth] {
        let byMonth = Dictionary(months.map { ($0.month, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<max(count, 0)).reversed().map { back in
            let month = thisMonth.advanced(by: -back)
            return byMonth[month] ?? .empty(month)
        }
    }

    /// Everything paid out so far. Nil when nothing has been, and when the
    /// paid months are in more than one currency (no honest single sum).
    var paidToDate: PayoutAmount? {
        let paid = months.compactMap { $0.paidAt == nil ? nil : $0.earned }
        guard let currency = paid.first?.currency,
              paid.allSatisfy({ $0.currency == currency }) else { return nil }
        return PayoutAmount(cents: paid.reduce(0) { $0 + $1.cents }, currency: currency)
    }
}
