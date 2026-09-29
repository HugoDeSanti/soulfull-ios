//
//  InstructorDirectory.swift
//  Soulfull Gatherings
//
//  Every published guide, and which guide each written practice is credited
//  to — read once and shared. A practice's or a digital retreat's page looks
//  its guide up here to show the "Your guide" card and open the profile.
//
//  Fails soft and silently, like presence. Offline, or for content with no
//  guide, the card simply isn't there. Nothing else on a page waits for it.
//

import SwiftUI

@Observable @MainActor
final class InstructorDirectory {

    static let shared = InstructorDirectory()

    /// Published guides, in the team's order.
    private(set) var instructors: [Instructor] = []
    /// Written practices' guides, keyed "exercise-4" (`PracticeCredit.key`).
    private(set) var credits: [String: String] = [:]
    private var inFlight: Task<Void, Never>?

    func instructor(id: String?) -> Instructor? {
        guard let id else { return nil }
        return instructors.first { $0.id == id }
    }

    /// The guide a written practice is credited to, if any.
    func instructorID(kind: PracticeContentKind, contentID: Int) -> String? {
        credits["\(kind.rawValue)-\(contentID)"]
    }

    /// Cheap from every screen that shows a guide: concurrent callers share one
    /// request, and `SupabaseService` caches the catalog for five minutes.
    func refresh() async {
        if let inFlight { await inFlight.value; return }
        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func load() async {
        #if DEBUG
        if Self.isPreview {
            instructors = Self.fixture
            credits = Dictionary(uniqueKeysWithValues: Self.fixtureCredits.map { ($0.key, $0.instructorID) })
            return
        }
        #endif
        // Each kept on failure: a dropped request must not take a guide off a
        // page that was showing one.
        do {
            instructors = try await SupabaseService.shared.fetchInstructors()
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Instructors unavailable: \(error.localizedDescription)")
        }
        do {
            let rows = try await SupabaseService.shared.fetchPracticeCredits()
            credits = Dictionary(rows.map { ($0.key, $0.instructorID) }, uniquingKeysWith: { a, _ in a })
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Practice credits unavailable: \(error.localizedDescription)")
        }
    }

    // MARK: - DEBUG fixture

    /// `-preview-instructors`: two guides with libraries, followers, faces and
    /// credits on written practices, so every page with a guide can be seen
    /// (and tested) whatever the live data holds. Browsed as a member — the
    /// shell's account gate lets it through — unless `-preview-guest` is
    /// passed too. Always false in Release.
    nonisolated static var isPreview: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-preview-instructors")
        #else
        false
        #endif
    }

    /// With `-preview-guest` as well, the fixture is browsed as a guest, so
    /// Follow and every practice meet the account gate — what
    /// `InstructorProfileTests` checks.
    nonisolated static var isPreviewMember: Bool {
        #if DEBUG
        isPreview && !CommandLine.arguments.contains("-preview-guest")
        #else
        false
        #endif
    }

    /// The viewer's id on their own face in "Followed by" when there is no
    /// session to take it from — the fixture member, in practice. Outside
    /// `#if DEBUG` because `InstructorProfileView` reads it in every build:
    /// inside, Release didn't compile.
    static let previewSelf = UUID(uuidString: "00000000-0000-0000-0000-00000000bbbb")!

    #if DEBUG
    static let fixture: [Instructor] = [
        Instructor(id: "alma-guerra", name: "Alma Guerra", title: "Breathwork · Somatic therapy",
                   // Fixture copy: about the teaching, never a biography —
                   // these names also appear on real content.
                   bio: "Slow, trauma-aware breathwork that meets the body where it actually is. Less about pushing through, more about noticing what is already here.\n\nThe guide behind Finding Ground. Every session is recorded in one take, in the room where it is taught.",
                   photoUrl: nil),
        Instructor(id: "mara-sole", name: "Mara Solé", title: "Meditation · Movement",
                   bio: "Stillness for people who are sure they can't sit still.",
                   photoUrl: nil),
    ]

    /// Alma: the first movement sequence and the first recipe. Mara: the
    /// gratitude prompt. Everything else has no guide, so its page has no card.
    /// The pages themselves are the live tables; the profile's library
    /// resolves these against `WrittenLibrary.mock`, which carries all three.
    static let fixtureCredits: [PracticeCredit] = [
        PracticeCredit(kind: .exercise, contentID: 1, instructorID: "alma-guerra"),
        PracticeCredit(kind: .recipe, contentID: 1, instructorID: "alma-guerra"),
        PracticeCredit(kind: .journal, contentID: 3, instructorID: "mara-sole"),
    ]

    private static func member(_ n: Int, _ name: String) -> CommunityMember {
        CommunityMember(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
                        displayName: name, avatarUrl: nil)
    }

    /// Alma: 212 followers — small enough that one follow visibly moves the
    /// number — following 12 guides, three faces. Mara: large, compacted,
    /// already followed.
    static func fixtureSocial(for id: String) -> InstructorSocial? {
        switch id {
        case "alma-guerra":
            return InstructorSocial(followers: 212, following: 12, followedByMe: false, isMe: false,
                                    faces: [member(1, "Theo R."), member(2, "Nia K."), member(3, "Mateo V.")])
        case "mara-sole":
            return InstructorSocial(followers: 75_712, following: 3, followedByMe: true, isMe: false,
                                    faces: [member(1, "Theo R.")])
        default:
            return nil
        }
    }

    static func fixtureLibrary(for id: String) -> InstructorLibrary {
        switch id {
        case "alma-guerra":
            let sessions: [PracticeSession] = [
                .init(id: 6, category: .breathwork, title: "Breath of Fire", lead: "Alma Guerra", mediaKind: .video, storagePath: "", durationSeconds: 540, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "An energizing kundalini practice to wake the body.", instructorID: id),
                .init(id: 21, category: .somatic, title: "Settling the Nervous System", lead: "Alma Guerra", mediaKind: .audio, storagePath: "", durationSeconds: 780, imageUrl: "retreat-images/sedona-2026-06.jpg", blurb: "", instructorID: id),
                .init(id: 22, category: .meditation, title: "Resting in the Exhale", lead: "Alma Guerra", mediaKind: .audio, storagePath: "", durationSeconds: 600, imageUrl: "retreat-images/dolomites-2027-09.jpg", blurb: "", instructorID: id),
            ]
            return InstructorLibrary(programs: Program.mock.filter { $0.instructorID == id },
                                     sessions: sessions,
                                     credits: fixtureCredits.filter { $0.instructorID == id },
                                     library: .mock)
        default:
            return InstructorLibrary(programs: [], sessions: [],
                                     credits: fixtureCredits.filter { $0.instructorID == id },
                                     library: .mock)
        }
    }
    #endif
}
